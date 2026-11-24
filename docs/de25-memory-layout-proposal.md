# DE25-Nano HPS-DDR layout — a proposal

**Status: a proposal, desk study.** Nothing here has been on hardware, and this document changes
no DTS, no script and no code. The image keeps today's layout
([`dts-mister-fpga-interface.md`](dts-mister-fpga-interface.md) §7), which follows a third-party
DE25 port so that port's bitstreams and Main run here unchanged. This document asks what the
layout *ought* to be, so both ports can agree on one before either has an installed base.

Evidence tags: **[S]** read from source (the file is named), **[M]** measured on hardware,
**[E]** an estimate, **[U]** unverified. "Stock Main" is the published DE10 Main_MiSTer; "stock
`sys/`" and "stock core" are the published DE10 framework and cores, read from local checkouts.
"The port" is the third-party DE25 port: its fabric top (`golden_top.v`), its Main and its notes.

---

## Summary (written to be forwarded)

*To the author of the DE25 port: a proposal for where things live in the HPS's 1 GiB of LPDDR4,
so that your shell and Main and ours can run each other's bitstreams and images.*

Your port already has the two ideas this proposal is built on. The fabric relocates a core's
DE10 DDR address by setting bit 31, so a core keeps its DE10 addresses. And the scaler's base is a
register the HPS writes, not a constant in the bitstream. Because of the second, almost everything
below is a change of *values*: no bitstream is rebuilt.

**The proposal in one line: the DE25 map is the DE10 map plus `0x8000_0000`, everywhere.**

| | your layout today | proposed | DE10 |
|---|---|---|---|
| Linux | up to `0x9DFF_FFFF`, plus `0xA200_0000`–`0xAFFF_FFFF` | up to `0x9FEF_FFFF` (`mem=511M`) | `mem=511M` |
| scaler scratch | `0x9E00_0000` | `0xA000_0000` | `0x2000_0000` |
| Main's framebuffer | `0xA000_0000` | `0xA200_0000` | `0x2200_0000` |
| core DDR | `0xB000_0000`, 256 MiB | `0xA000_0000`, 512 MiB, the two video tiles inside it as on the DE10 | `0x2000_0000`, 512 MiB |

What would change on your side:

1. the value the boot service writes to `fbcfg`: `0x9E00_0000` becomes `0xA000_0000`;
2. `FB_ADDR` in `video.cpp`: `0xA000_0000` becomes `0xA200_0000`, which is the stock formula with
   bit 31 set;
3. the DTS: all of `0xA000_0000`–`0xBFFF_FFFF` stays out of Linux, and `mem=511M`;
4. `fpga_mem()` in Main becomes the stock macro with bit 31 set, which gives the direct-DDR load
   path its window back.

Both video tiles slide up by the same 32 MiB, so the offset your fabric computes between them does
not change.

Why: DE10 cores use the low half of the window too. SNES MSU-1 data loads at `0x2060_0000` and can
run to 498 MiB, and the SNES RTL itself steps over 8 MiB at `0x2200_0000`, where the DE10's
framebuffer is. Minimig's shared folder is at `0x27FF_4000` and its network mailbox at
`0x1FF0_0000`. Stock Main accepts a CONF_STR or MRA load address anywhere from `0x2000_0000` to
`0x3FFF_FFFF`. With bit 31 set, all of those land between `0x9FF0_0000` and `0xBFFF_FFFF`, and
today that is where the scaler scratch, the framebuffer and part of Linux are. On the proposed map
each lands on reserved RAM beside its DE10 neighbours, so a ported core needs no address edits and
Main needs no per-core patch.

The cost: Linux has 479 MiB (the DE10's `mem=511M`, less the 32 MiB the firmware keeps at the
bottom) instead of the roughly 670 MiB your device tree leaves it. That is the trade the DE10 has
always made. If we want that RAM back later, the cleaner way is to
move core RAM to the FPGA-side LPDDR4 (your LPDDR4B coexistence test is the first evidence for
it), and the contract below is shaped so that cores and Mains would not notice the move.

The contract we would both keep, so the layout can still move after this:

1. a core's addresses are the DE10's, always;
2. one translation, `+0x8000_0000`, applied once in the shell and once in Main;
3. the device tree says where the tiles are, and Main reads it (the framebuffer from `/dev/fb0`,
   the rest from the reserved-memory nodes) instead of holding constants;
4. the shell publishes what it assumes (the translation, the window, the scaler's size) in a small
   register block beside `fbcfg`, so a mismatched shell and image refuse instead of corrupting
   memory.

Nothing here is urgent, and nothing breaks what you have shipped: our image keeps your layout
until both sides are ready. The reasoning and the sources follow.

---

## 1. What a DE25 layout must give a DE10 core

### 1.1 Who uses which part of the DE10's window

The DE10 has 1 GiB of HPS DDR3 at `0x0`. Linux has the low half (`mem=511M`), and everything from
`0x1FF0_0000` up is shared with the fabric. Stock Main's own bound for a core address is
`[0x2000_0000, 0x4000_0000)`: a savestate base, a CONF_STR load address and a mapped load all test
exactly that. [S: stock Main `user_io.cpp:744,948,2880`, `menu.cpp:2438`]

| DE10 address | size | user | source [S] |
|---|---|---|---|
| `0x1FF0_0000` | 64 KiB | Minimig's A2065 network mailbox, below the window | `support/minimig/minimig_a2065_ddr3.h:17-18` |
| `0x1FFF_F000` | 4 KiB | the handoff page: the core-type handshake with U-Boot, and Main's `sdram_sz` and `altcfg` | `user_io.cpp:1329,1363`, `fpga_io.cpp:398,601` |
| `0x2000_0000` | 24 MiB, or 6 MiB | ascal's scratch. `RAMBASE` is a constant in `sys_top`; `RAMSIZE` is 8 MiB per buffer (2 MiB under `MISTER_SMALL_VBUF`) and ascal uses three | stock `sys/sys_top.v:716-720`, `sys/ascal.vhd:97,436-443`; Main `scaler.h:31` |
| `0x2060_0000` up | to 498 MiB | SNES MSU-1 data: Main sends the core this base and loads the `.msu` file there, up to `0x1F20_0000` bytes, so it can reach the top of the window | `support/snes/snes.cpp:521-525`, `user_io.cpp:2880-2888` |
| `0x2200_0000` | 23.7 MiB | Main's framebuffer: `FB_ADDR` = window + 32 MiB, three 1080p 32-bit buffers. `/dev/fb0` is the first 8 MiB; the palette is 4 KiB below the base Main hands the scaler | `video.cpp:36-37,2414`; stock `sys/sys_top.v:1030` |
| `0x27FF_4000` | 8 KiB | Minimig's shared folder | `support/minimig/minimig_share.cpp:22` |
| `0x3000_0000` up | per core | ao486 memory and its share at `0x300C_E000`; N64 RDRAM (8 MiB), its 64DD IPL at `0x30C0_0000` and fast-load at `0x3200_0000`; PSX and NeoGeo RAM; Saturn's CD buffer at `0x3100_0000`; MD+ audio ring; the C64's disk images | `support/x86/x86.cpp:49`, `x86_share.cpp:46`, `n64/n64.cpp:28,1574,1614-1615`, `neogeo/neogeo_loader.cpp:240,383`, `saturn/saturncdd.cpp:11`, `megadrive/mdplus.cpp:22-23`, `c64/c64.cpp:430-431` |
| `0x3C00_0000`–`0x3FFF_FFFF` | per core | savestates, declared in CONF_STR: N64 `SS3C000000:1000000`, PSX `SS3E000000:400000`, NES `SS3E000000:200000`, SNES `SS3F800000:100000` | each core's top-level `.sv` |
| anywhere in the window | file-sized | a CONF_STR `F…` entry's fourth field, or an MRA `<rom address=…>` | `user_io.cpp:940-952`, `menu.cpp:2434-2438`, `support/arcade/mra_loader.cpp:344` |

Three of these are constants in *core RTL*, not only in Main:

- **The address prefix.** PSX and NeoGeo drive `DDRAM_ADDR = {4'b0011, addr[27:3]}`: 256 MiB at
  `0x3000_0000`, and no way to leave it. [S: `PSX_MiSTer/rtl/ddram.sv:85`,
  `NeoGeo_MiSTer/rtl/mem/ddram.sv:70`] The SNES drives a full 32-bit address. [S:
  `SNES_MiSTer/rtl/ddram.sv:61,74`]
- **The SNES's step over the framebuffer.** `msu_data_store` adds 8 MiB to every MSU address at or
  above `0x2200_0000`, and Main's loader leaves the same 8 MiB gap. [S:
  `SNES_MiSTer/rtl/chip/MSU1/msu_data_store.sv:39-41`; stock Main `user_io.cpp:2882,2888`] The DE10
  framebuffer's address is part of the SNES core.
- **A core's own framebuffer.** PSX hands the scaler `FB_BASE = 0x3000_0000` plus a frame offset;
  N64 does the same from its video block. [S: `PSX_MiSTer/PSX.sv:51`, `N64_MiSTer/N64.sv:196`]

And one is a constant in the SNES *project*: it builds with `MISTER_SMALL_VBUF`, so ascal stops at
`0x205F_FFFF` and MSU-1 data begins on the next byte. [S: `SNES_MiSTer/SNES.qsf:57`]

### 1.2 An offset works; identity cannot

The DE10's addresses cannot be the DE25 CPU's. On Agilex 5 the HPS DDR is at
`0x8000_0000`–`0xBFFF_FFFF`, and CPU-physical `0x2000_0000` is the lightweight bridge. The port
found this the direct way: stock `FB_ADDR` landed in bridge register space. [S: the port's
`video.cpp:36-37`] The port's fabric-to-DDR path, by contrast, is identity-mapped: fabric address X
is DDR physical X. [S: the port's `L4_DESIGN.md:54-60`]

So a translation is needed twice, once in the shell and once in Main. It can be a single wire,
because the two boards have the same amount of HPS DDR on a 1 GiB boundary:

```
DE25 physical = DE10 address | 0x8000_0000        (the same as + 0x8000_0000 below 1 GiB)
```

That maps the whole DE10 DDR, `0x0`–`0x3FFF_FFFF`, onto the whole DE25 DDR. The DE10's window is the
top half of its DDR, and its image is the top half of the DE25's: `0xA000_0000`–`0xBFFF_FFFF`. The
low tiles follow: `0x1FF0_0000` becomes `0x9FF0_0000`.

The OR form has one more property. It does nothing to an address that is already a DE25 physical
address. The fabric receives both kinds: constants baked into a core (DE10 numbers), and addresses
the HPS sends at run time (the framebuffer base in `UIO_SET_FBUF`, the ALSA ring's address, the
scaler base). One OR where addresses enter the DDR port serves both, with no per-master rule.

The port's fabric already applies this bit to a core's DDRAM channel (it sets bit 28 of the 64-bit
word address), and its Main applies `| 0x80000000` to a savestate base. [S: the port's
`golden_top.v:223-224,1581-1582`, `user_io.cpp:774-779`] The rule is in place. What differs is
which RAM is reserved underneath it.

### 1.3 The requirements

| # | requirement | why |
|---|---|---|
| R1 | one contiguous 512 MiB of reserved RAM at the image of `0x2000_0000`–`0x3FFF_FFFF` | stock Main's bound; MSU-1's reach; a full-address core can emit any of it |
| R2 | one translation for every address, `\| 0x8000_0000` | a per-range rule needs per-core knowledge the shell does not have |
| R3 | the scaler scratch at the image of `0x2000_0000`, at most 6 MiB for a core that loads at `0x2060_0000` | the SNES project constant |
| R4 | `/dev/fb0`'s 8 MiB at the image of `0x2200_0000` | the SNES RTL constant; stock `FB_ADDR` |
| R5 | reserved RAM at the image of `0x1FF0_0000` and `0x1FFF_F000` | the A2065 mailbox; the handoff page's `sdram_sz` and `altcfg` |
| R6 | nothing of Linux's inside any address a stock core can emit | fabric masters are not behind the SMMU (it is off), so a stray write is silent kernel corruption |

R6 is why the window is more than capacity. A core built from DE10 RTL with a `0x2…` or a full
32-bit address *can* drive any address in the window, whether or not it should. The port's Main
already guards against exactly this: it refuses a savestate base below `0x3000_0000` "instead of
mapping kernel RAM by accident". [S: the port's `user_io.cpp:762-770`]

---

## 2. Linux's budget

**The floor on the DE25 is 32 MiB lower than the DE10's.** Mainline's Agilex 5 `.dtsi` reserves
`0x8000_0000` + 32 MiB for BL31 and the service buffer (`service_reserved`, `no-map`). [S:
`arch/arm64/boot/dts/intel/socfpga_agilex5.dtsi`, node `svcbuffer@0`;
[`de25-dts-rationale.md`](de25-dts-rationale.md) U9] The DE10 has no such tile. So `mem=511M` here
means 479 MiB for Linux, and today's `mem=479M` means 447 MiB.

| | figure | tag |
|---|---|---|
| DE10, `mem=511M`: `MemTotal` | 487 MiB (498 652 kB) on one kernel build, 489 MiB on another | [M: the greenfield rig, 2026-10] |
| DE10, the 487 MiB boot: `MemAvailable` with stock Main installed | 420 MiB (430 528 kB) | [M: same] |
| stock Main, resident | about 8 MB | [U: the owner's figure] |
| greenfield Main at the menu with the HD OSD, resident and locked | 68.8 MB resident, 69.7 MB locked; of it Slint 12.8 MB, heap 25.9 MB, stacks and other anonymous 21 MB | [M: DE10 rig, 2026-10-15] |
| greenfield Main after a large arcade romset, back at the menu | 71.9 MB | [M: same] |

A DE25 estimate, to be replaced by the first boot's `/proc/meminfo`:

| item | MiB | tag |
|---|---|---|
| kernel image, `struct page` array, early reservations (arm64; the DE10's arm32 kernel costs 24) | 35–45 | [E] |
| kernel at run time: slab, page tables, stacks, network buffers | 20–30 | [E] |
| base userland: init, udev, sshd, Samba, Bluetooth, Wi-Fi | 40–60 | [E] |
| greenfield Main with the HD OSD, on aarch64 (the measured 70 MB × 1.2–1.3) | 85–90 | [E] |
| **steady state** | **180–225** | |
| left of 479 MiB (layout A) for page cache and transients | 255–300 | |
| left of 447 MiB (today) | 220–265 | |

The transients are what that remainder is for: the Python downloader, an arcade romset staged
before it is sent (the rig once showed 207 MB before a fix made it transient), the buffers the
FPGA service fills with a bitstream, and the page cache that keeps CD and CHD streaming smooth.

**Verdict: adequate, not generous.** 479 MiB is the DE10's envelope less the firmware's 32 MiB,
and the DE10's envelope runs greenfield with the HD OSD today. 447 MiB also works. The 32 MiB
between them is not what decides the layout; R1–R6 decide it. But there is no reason to spend
32 MiB of Linux on a scaler scratch below the window when the start of the window is where a
DE10 core expects the scaler to be (§3.1).

---

## 3. Candidate layouts

All figures are MiB of the 1024. "Linux" is what is left after the firmware's 32.

| layout | Linux | reserved window a core can use | MSU-1 | Minimig share | core RTL addresses | Main patches per core |
|---|---|---|---|---|---|---|
| DE10, for reference | 511 | 512 at `0x2000_0000` | 498 | works | — | — |
| **A**: DE10 + `0x8000_0000` | 479 | 512 at `0xA000_0000` | 498 | works | unchanged | none |
| **B**: today's image (the port's video layout, the aperture kept whole) | 447 | 480 at `0xA200_0000`; the image of `0x2000_0000` +32 MiB is the framebuffer | collides with the framebuffer; 464 with a Main patch | works with a host that translates the whole window; the port's Main maps `0xB7FF_4000` | unchanged | SNES; Minimig's A2065 |
| **B′**: the port's own device tree | 672 | 256 at `0xB000_0000` | no window; 248 at most with a Main patch | lands in Linux; the port's Main maps `0xB7FF_4000`, which a stock Minimig does not address | Minimig needs edits | every core that uses an address below `0x3000_0000` |
| **C2**: core RAM in the FPGA-side LPDDR4, end state | about 960 | 512, or all 1024, in LPDDR4B | 498 | works | unchanged | none |

### 3.1 Layout A — the DE10 plus `0x8000_0000`

```
0x8000_0000  +---------------------------------------------+
             | firmware: BL31, svc buffer           32 MiB |
0x8200_0000  +---------------------------------------------+
             | Linux (mem=511M)                    479 MiB |   DE10: 0x0000_0000, 511 MiB
0x9FF0_0000  +---------------------------------------------+
             | ddr-low: A2065 mailbox, spare      1020 KiB |   DE10: 0x1FF0_0000
0x9FFF_F000  | handoff page                          4 KiB |   DE10: 0x1FFF_F000
0xA000_0000  +=============================================+   the core window, 512 MiB
             | scaler scratch                       32 MiB |   DE10: 0x2000_0000
0xA200_0000  | Main's framebuffer; fb0 = first 8    32 MiB |   DE10: 0x2200_0000
0xA400_0000  | core DDR                            192 MiB |   DE10: 0x2400_0000
0xB000_0000  | core DDR                            256 MiB |   DE10: 0x3000_0000
0xBFFF_FFFF  +=============================================+
```

| DE25 | size | DE10 twin | what |
|---|---|---|---|
| `0x8000_0000` | 32 MiB | none | firmware, `service_reserved`, as mainline has it |
| `0x8200_0000`–`0x9FEF_FFFF` | 479 MiB | `0x0`–`0x1FEF_FFFF` | Linux, `mem=511M` |
| `0x9FF0_0000` | 1020 KiB | `0x1FF0_0000` | `ddr-low` |
| `0x9FFF_F000` | 4 KiB | `0x1FFF_F000` | the handoff page's twin; no boot-stage reader on this board, Main's scratch only |
| `0xA000_0000` | 32 MiB | `0x2000_0000` | scaler scratch: the port's one 32 MiB buffer, or stock ascal's 3 × 8 MiB; 3 × 2 MiB for a core that loads at `0x2060_0000` |
| `0xA200_0000` | 32 MiB | `0x2200_0000` | Main's three buffers (23.7 MiB); `/dev/fb0` is the first 8 MiB, `smem_start` `0xA200_1000` |
| `0xA400_0000` | 448 MiB | `0x2400_0000` | core DDR; the high 256 MiB is where a `4'b0011` core lives |
| `0xA000_0000` | 512 MiB | `0x2000_0000` | the aperture, `mister_ddr_aperture`, write-combined; mask `0x1FFF_FFFF` |

The two video tiles are *positions inside the window*, as on the DE10, not partitions. A core that
does not use one owns the bytes, which is how MSU-1 data runs from `0xA060_0000` to the top with
its 8 MiB step at `0xA200_0000`.

What it gives: R1–R6, all six. One rule in the shell. `fpga_mem()` in Main is the stock macro with
bit 31 set. The stock SNES RTL and stock Main's SNES loader are correct as they stand.

What it costs: Linux has 479 MiB. Every boot reserves 512 MiB whether the core uses 2 MiB or all of
it, as on the DE10.

**Why the scaler goes inside the window and not below it.** On the DE10 the scaler owns the first
bytes of the window in every bitstream, so no working DE10 core uses them for anything else.
Placing the scratch below the window frees nothing a core can use and takes 32 MiB from Linux. It
also sits on the image of the DE10's low tiles: `0x9E00_0000` + 32 MiB covers `0x9FF0_0000` and
`0x9FFF_F000`.

### 3.2 Layout B — today's layout, and what breaks

```
0x8000_0000  +---------------------------------------------+
             | firmware                             32 MiB |
0x8200_0000  | Linux (mem=479M)                    447 MiB |
0x9DF0_0000  | ddr-low, handoff                      1 MiB |   not the image of 0x1FF0_0000
0x9E00_0000  | scaler scratch                       32 MiB |   covers the image of 0x1FF0_0000
0xA000_0000  +=============================================+
             | Main's framebuffer                   32 MiB |   the image of 0x2000_0000
0xA200_0000  | core, low: reserved here,           224 MiB |   the port gives this to Linux
0xB000_0000  | core, high                          256 MiB |   the image of 0x3000_0000
0xBFFF_FFFF  +=============================================+
```

The port's video layout fixed two real faults, and both fixes are right in kind: a kernel-reserved
region instead of a freeable hugepage, and a scaler scratch disjoint from the framebuffer so the
console is not overwritten by live video. [S: the port's `tools/fb_autostart.sh:6-15`,
`video.cpp:38-50`] What it did not have in view is the low half of the DE10 window. Under the
bit-31 rule:

| DE10 user | lands at | which today is | result |
|---|---|---|---|
| SNES MSU-1 data, `0x2060_0000` | `0xA060_0000` | inside Main's framebuffer | data and menu overwrite each other |
| the SNES's 8 MiB step, `0x2200_0000` | `0xA200_0000` | core RAM here, Linux on the port | steps over the wrong 8 MiB |
| ascal's stock base, `0x2000_0000` | `0xA000_0000` | Main's framebuffer | harmless on the port, whose base is a register |
| Minimig share, `0x27FF_4000` | `0xA7FF_4000` | reserved here, Linux on the port | the port's Main maps `0xB7FF_4000` instead, so the core's address has to change |
| A2065 mailbox, `0x1FF0_0000` | `0x9FF0_0000` | the top MiB of the scaler scratch | the port's Main maps `0xBFF0_0000` instead, so the core's address has to change |
| a CONF_STR or MRA load below `0x3000_0000` | `0xA…` | as above | the port's Main refuses every direct-DDR load |

The last row is the port's own statement: "No direct-DDR ROM window is defined for this port yet",
and savestates below `0x3000_0000` are disabled. [S: the port's `user_io.cpp:762-770,3141-3148`] So
the low half is not wrongly defined on the port; it is not defined yet. That is the opening for
this proposal.

B can be patched per core. MSU-1, for example, could be given a base above the framebuffer: Main
sends the core its base. That needs a Main change, and since the RTL's step at `0x2200_0000` still
applies it leaves 464 MiB for the data where the DE10 allows 498. On the port's own device tree the
base would be near `0x3000_0000`, and the room at most 248 MiB. Each such patch is a place where a
DE25 core stops being its DE10 source re-synthesised.

### 3.3 Layout C — spending less of the HPS's RAM

**C1. A window sized per core.** Could the reservation follow the core's real need? Only with a
declaration, and stock cores declare little:

- the savestate window, as `SS<base>:<size>` in CONF_STR; [S: stock Main `user_io.cpp:725-748`]
- a load *address*, as a CONF_STR field or an MRA attribute, with no size;
- nothing for the RAM a core uses by itself. PSX's and NeoGeo's use of `0x3000_0000` up is
  visible only as an RTL prefix.

A host can carry a per-core table (greenfield's core manifests name each core's windows), but the
bitstream does not say it, and a window only helps Linux if the RAM can be handed back. That is
C3. As a boot-time choice it is simple: a second device tree with a smaller window. The port
restarts through RSU on a core switch, where a per-core `mem=` is conceivable; our plan
reconfigures through the SDM without a reboot, where it is not.

**C2. Core RAM in the FPGA-side LPDDR4.** The board's second 1 GiB bank, LPDDR4B, belongs to the
fabric. [S: DE25-Nano manual §3.7.4] It is the same size as the DE10's entire HPS DDR, so a core's
address can be used as it is, masked to 30 bits, and a shell can show the bank to the HPS through
the first HPS-to-FPGA bridge window, which is also 1 GiB (`0x4000_0000`). [U: the window's size is
from Altera's documents, not from this board] Main's translation becomes `+0x4000_0000` and nothing
else in Main changes.

| | HPS LPDDR4 through the fabric-to-DDR port (the port today) | FPGA-side LPDDR4B |
|---|---|---|
| who else is on it | the CPU, and ascal: one 256-bit port at 100 MHz shared through an arbiter in which ascal has priority [S: the port's `L4_DESIGN.md:48-60`, `fb_ddram_arb.v` header] | nobody |
| ceiling | 3.2 GB/s for all masters together; a 1080p 32-bit framebuffer scan-out alone is 0.5 GB/s [E] | about 10 GB/s at the pins (32 lines, the manual's 1333 MHz) before the controller [E] |
| a core's worst-case wait | unbounded on paper: it waits for ascal to go idle | its own controller's |
| HPS access | native RAM speed; cache-coherent through the ACE5-Lite translator, by the port's test [S: the port's `PROJECT_STATUS.md` §5d] | through the bridge, uncached; rate unmeasured [U]. A 498 MiB load is bounded by the SD card either way |
| when it exists | always | only after the core is configured and the bank has calibrated, on every load [U: time unmeasured] |
| hazard | a stray write can reach Linux | none to Linux; but every HPS access is a bridge access, with the unconfigured-fabric SError hazard |
| cost to a core's build | none | an EMIF and its interconnect in every bitstream; the port records placement failures it traced to the bank's IP selection and PLL pinning [S: the port's `L4_DESIGN.md:3-9`] |

The port's ascal uses HPS LPDDR4 today, and LPDDR4B is disabled in its production cores. A
60-second coexistence test passed: 211 full passes of the 1 GiB bank with no errors while Linux
ran. [S: the port's `L4_DESIGN.md:3-9`] In the end state only Main's framebuffer needs HPS RAM,
because the CPU draws into it: Linux would have about 960 MiB.

C2 is the right long-term home for a core's own RAM, on latency grounds as much as memory. It is a
shell project, not a layout agreement. It should not hold up the agreement, and the agreement
should not foreclose it.

**C3. Linux gets the RAM back when the core does not need it.** The kernel mechanism is CMA: a
reserved-memory node that is `shared-dma-pool` and `reusable` at a fixed `reg` is used by Linux
for movable pages until a driver claims it, when the pages are migrated out. Claiming a whole area
yields a known address, so two areas (the low 192 MiB, the high 256 MiB) could be claimed per core.

| question | answer |
|---|---|
| is it in the kernel we pin (7.4-rc4)? | the mechanism is long-standing; our DE25 `linux.config` enables no CMA symbol today [S] |
| what must be written | a small driver to claim and release an area and expose it for `mmap`; UIO cannot [E] |
| can a claim fail? | yes: a pinned page (I/O in flight, a long-term pin) cannot move, and the claim returns busy. The failure is a core that will not load, at run time, depending on what else the system was doing |
| what does a claim cost? | it migrates every page in the area; time grows with what Linux had put there [U] |
| what does Linux really gain? | only movable pages (page cache, anonymous memory) may use the area. Kernel allocations cannot, so "free" overstates what the kernel can use |
| what is the worst case? | releasing an area while a bitstream that addresses it is still running. With no SMMU, the fabric then writes into pages Linux has reused |
| real-time | greenfield locks its memory; a locked page can still be migrated, and a thread that touches it mid-move waits |

It is feasible and it is the highest-risk option here, for a gain (up to 448 MiB of page cache
while a small core runs) that the DE10 has never had and has not missed. Not recommended. If the
RAM is wanted, C2 returns more of it with no shared-ownership hazard.

---

## 4. Recommendation

**Adopt layout A as the common layout, keep the port's scaler-base register, and agree the
contract in §5 so that C2 stays open.**

A is the only candidate that meets R1–R6 with stock core addresses and no per-core host patch. Its
cost is 479 MiB for Linux, which §2 finds adequate. And it is nearly free to reach from the port's
layout, because the port already has the translation and already takes the scaler base from the
HPS.

### 4.1 What the port changes

| what | from | to | rebuild |
|---|---|---|---|
| the scaler base its boot service writes to `fbcfg` | `0x9E00_0000` | `0xA000_0000` | none: a script constant |
| `FB_ADDR` in its Main | `0xA000_0000` | `0xA200_0000` | Main |
| its device tree: the reserved tiles and the `MiSTer_fb` node | scaler `0x9E00_0000`, framebuffer `0xA000_0000`, core `0xB000_0000` | scaler `0xA000_0000`, framebuffer `0xA200_0000`, everything from `0x9FF0_0000` up reserved; `mem=511M` | DTB |
| `fpga_mem(x)` in its Main | the stock macro, with the direct-DDR path refused | `0xA0000000 \| (x & 0x1FFFFFFF)`, path enabled | Main |
| Minimig share, A2065 mailbox | `0xB7FF_4000`, `0xBFF0_0000` | the images of the DE10's addresses: `0xA7FF_4000`, `0x9FF0_0000` | Main |
| the fabric's translation | bit 31 on the core DDRAM channel | the same, stated as the rule for every master that is added | none |

No shipped bitstream is rebuilt. The fabric forms Main's framebuffer address as an offset from the
scaler base, and both move by 32 MiB, so the offset is unchanged. [S: the port's
`golden_top.v:1387-1403`]

Two things the port's shell needs for a full DE10 core set, in any layout:

- **A scaler no larger than the DE10's for a core that needs the bytes.** The port's ascal has one
  32 MiB buffer. A SNES build has to keep its DE10 size (2 MiB buffers), or MSU-1 data at
  `0xA060_0000` is inside the scratch.
- **Reach for a core's own framebuffer.** The port's ascal addresses 256 MiB above the scaler base.
  PSX's `FB_BASE` lands at `0xB000_0000`, which is 256 MiB above `0xA000_0000` and 288 MiB above
  today's base, so it is out of reach in both layouts. Stock `sys_top` gives ascal a 28-bit
  address in 16-byte words, 4 GiB. [S: the port's `golden_top.v:1395-1398`; stock
  `sys/sys_top.v:696`]

### 4.2 What this image changes

Nothing until the port's side is ready. Then, in one commit:

- the DTS returns to the DE10's tiles at `+0x8000_0000`: `ddr-low` at `0x9FF0_0000`, the handoff
  twin at `0x9FFF_F000`, the scaler tile at `0xA000_0000`, `mister-fb` at `0xA200_0000`, core RAM
  from `0xA400_0000`; `mem=511M` on the extlinux line;
- the `mister_scaler` UIO node and its DE25-only udev rule go away: the scaler is inside
  `mister_ddr_aperture` at offset 0, as on the DE10, and the DE25 again takes the DE10's rules file
  unchanged;
- greenfield's DE25 board row takes the aperture its bring-up plan already names,
  `{0xA000_0000, 512 MiB}` (the row is unsourced today), and every named region is the DE10's
  entry at `+0x8000_0000`, including the one below the aperture. No region needs a per-board
  address.

### 4.3 Order

1. **Now: agree the constant.** The translation, `0x8000_0000`, is the one value in every
   bitstream. Both sides already use it. Agreeing it costs nothing and is the only thing a later
   change cannot move without re-synthesising every core.
2. **Next: stop holding constants in the hosts** (§5, rules 3 and 4). After this, either Main runs
   on either device tree.
3. **Then: move the tiles.** A device tree, a script value and, on the port, one Main rebuild.
4. **Later, if wanted: C2**, per shell, behind the same contract.

---

## 5. What keeps this easy to change

The layout has moved once on this image and twice on the port (its framebuffer went from
`0x2200_0000` to `0x9E00_0000` to `0xA000_0000`). [S: the port's `video.cpp:50`] What makes a move
expensive is a constant in a host or a script, not the addresses themselves. The port's best idea
here is that the fabric *learns* the scaler base from a register and its Main reads it back. [S:
the port's `scaler.cpp:40-67`] The contract extends that idea until one constant is left.

**The minimal contract, for both Mains and both shells:**

| # | rule | who holds what |
|---|---|---|
| 1 | **A core's addresses are the DE10's.** In RTL, in CONF_STR, in an MRA, in `FB_BASE` | cores: DE10 numbers only |
| 2 | **One translation: CPU-physical = core address + K, and K = `0x8000_0000`.** The shell applies it to every address at the DDR port (as an OR). A host applies it in exactly one function | shell: one constant. Main: `fpga_mem()`; greenfield: `FpgaAperture::translate` with the board row's base |
| 3 | **The device tree is the layout.** A host reads the aperture's base and size from its UIO node (`/sys/class/uio/…/maps/map0/addr`, `size`), the framebuffer from `/dev/fb0` (`smem_start` − 4096 is `FB_ADDR`, on both boards), the scaler tile from its reserved-memory node | hosts: no address constants; no `FB_ADDR` |
| 4 | **The HPS tells the fabric the scaler base**, as the port does, with the value read under rule 3. Zero means the scaler is gated | boot service or Main: no constant |
| 5 | **The shell publishes what it assumes**, read-only, beside the base it is given | see below |
| 6 | **A shell never emits an address outside the window and the bases it was given.** | shell |

**The published block (rule 5).** Eight words are enough. On the port's shell they can extend the
`fbcfg` block; on a shell with our lightweight-bridge directory they are one directory entry kind.
The offsets below are a sketch; the meaning is the proposal.

| word | access | meaning | value in layout A |
|---|---|---|---|
| MAGIC, VERSION | RO | identifies the block and its revision | — |
| XLATE | RO | K: the CPU-physical address of core address 0 | `0x8000_0000` |
| WIN_BASE | RO | the CPU-physical base of the window the shell assumes | `0xA000_0000` |
| WIN_SIZE | RO | its size | `0x2000_0000` |
| SCALER_BASE | RW | written by the HPS; 0 gates the scaler (the port's existing word) | `0xA000_0000` |
| SCALER_SIZE | RO | the bytes the scaler may touch from that base: buffers × `RAMSIZE` | `0x0200_0000` on the port; `0x0060_0000` for a SNES build |
| CORE_LO, CORE_HI | RO | the lowest and one past the highest DE10 address this core can emit; both 0 means undeclared, assume the whole window | per core |

A host compares WIN_BASE and WIN_SIZE with the aperture the device tree gave it, and SCALER_SIZE
with the scaler tile, **before** it writes SCALER_BASE. On a mismatch it leaves the scaler gated
and says so. A wrong pairing of shell and image then fails at the menu, visibly, instead of
writing through a stale address.

CORE_LO and CORE_HI are the declaration §3.3 found missing. Nothing uses them in layout A. They are
what a per-core window or a CMA claim would need, and they cost a core two constants.

**What this buys.** With rules 1–5 in place:

| change | what has to move |
|---|---|
| resize or move the scaler tile or the framebuffer | the device tree |
| change `mem=` | the device tree and the extlinux line |
| move core RAM to LPDDR4B (C2) | the shell, which then publishes K = `0x4000_0000`, and the device tree's aperture node, which points at the bridge window. No core source, no Main source |
| per-core windows (C1, C3) | a kernel driver and a host policy; cores add CORE_LO and CORE_HI |
| move the window inside the HPS's DDR (a different K) | every bitstream is re-synthesised. This is the one constant to get right now |

---

## 6. What a DE25 core may change, and what it may not

A DE25 core is re-synthesised from DE10 source against a different `sys/`. That makes the shell
free to change and the core's own source the thing to protect: a port that edits core RTL has to
be repeated at every upstream release.

| stays identical: a core can see it | free to change: only the shell or the image sees it |
|---|---|
| the `DDRAM_*` port: a 29-bit address of 64-bit words (byte address ÷ 8), burst count, byte enables, busy and ready [S: stock `sys/sys_top.v:1692,1824`] | where the DDR is: K, and which bank backs the window |
| the numeric addresses: RTL prefixes, CONF_STR `SS` bases and load addresses, MRA addresses, `FB_BASE` | how many DDR ports there are and how they are arbitrated. The DE10 has three (one 128-bit for video, two 64-bit); the port has one 256-bit port and an arbiter [S: stock `sys/sysmem.sv:67,113,159`] |
| the scaler's first bytes at `0x2000_0000` and its per-core size (`MISTER_SMALL_VBUF`) | how the scaler gets its base: a constant on the DE10, a register here |
| the framebuffer's 8 MiB at `0x2200_0000`, and `FB_ADDR` = window + 32 MiB | the framebuffer tile's size beyond those 8 MiB |
| `hps_io`, CONF_STR, the status word, every `UIO_*` and file-transfer opcode | the carrier of the GPO/GPI pair (the FPGA manager on the DE10, a bridge register here) |
| | the CPU mapping's memory type; `mem=`; the handoff page's use; on-board SDRAM against the DE10's module |

The 29-bit word address spans 4 GiB, so a core is not confined by the port's width. It is confined
by its own prefix and by rule 6. That is as true on the DE10, where the address goes to the HPS
unmasked. [S: stock `sys/sysmem.sv:74-84,204`]

---

## 7. Open, and to measure

| # | what | how |
|---|---|---|
| 1 | Linux's real floor on the DE25 | `head -3 /proc/meminfo` on the first boot of each layout |
| 2 | the first bridge window's size and that it is usable for bulk data | Altera's documents say 1 GiB at `0x4000_0000`; unproven on this board |
| 3 | LPDDR4B calibration time after a full configuration | the port's bench; decides whether C2 is tolerable on every core load |
| 4 | HPS throughput into LPDDR4B through the bridge | a `dd`-style copy once a shell exposes it |
| 5 | whether the ACE5-Lite path lets the HPS map the window cached | the port reports coherence; our image maps it write-combined and has not measured |
| 6 | whether any published DE10 core relies on an address this table does not list | §1.1 is a grep of stock Main and five cores, not a survey of all of them |
| 7 | the block's encoding in rule 5 | belongs with the lightweight-bridge directory design, when video is reached |

## 8. Status, and the long-term placement question (operator, 2026-11-24)

**For now the DE25 image keeps the third-party port's layout as shipped** (scaler scratch `0x9E00_0000`, framebuffer
`0xA000_0000`, core window `0xB000_0000`, all on the HPS LPDDR4). Layout A above is a proposal to discuss, not a plan
of record. The long-term layout gets more thought before either side changes anything.

The question still open is which controller each region lives on. The board has two independent LPDDR4 controllers:
the HPS's hard interface and a separate FPGA-side one. The operator's starting position:

- **All of ascal on one controller, most likely the HPS one as it is now.** That means the scaler scratch AND the
  framebuffer it can read, so ascal has one memory port and no traffic split across controllers.
- **The FPGA-side bank left to the cores**, so core DDR traffic has a controller to itself.
- **No region that makes one block's traffic cross both controllers.**

Before deciding, measure or check these:

1. ascal's real bandwidth on the HPS bank at 1080p60 (input write, output read, framebuffer read), and its headroom
   next to Linux.
2. What the FPGA-side controller costs a core's shell: area, calibration time at each full reconfiguration, and
   whether it survives the reconfiguration sequences the port uses.
3. Core DDR latency and timing on the FPGA bank against the HPS path, for timing-sensitive cores (for example PSX's
   SPU cache in DDR3 mode).
4. How the HPS reaches core RAM on the FPGA bank for bulk loads (ROM, MSU-1 data), and for savestates: the bridge
   window speed, or a fabric DMA from an HPS staging buffer.
5. Side effects not yet listed. An FPGA developer's review of the whole placement is owed before it is decided.
