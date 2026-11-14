# The MiSTer HPS<->FPGA interface in the device tree

How the DE10-Nano's fixed HPS<->FPGA resources are described in its device tree, what each
node maps and with which page attribute, the evidence for every address, what is left out and
why, and how userspace uses each node. The DTS itself carries only a header line per node group
and the one-line hazards that must sit next to a node; everything else is here.

Patches (shared by the 6.18 and RT lines; the beta `series` symlinks them):

| patch | what |
|---|---|
| `linux-patches/0072-dts-de10nano-MiSTer-fpga-interface.patch` | the device-tree description below |
| `linux-patches/0045-uio-writecombine.patch` | `UIO_MEM_PHYS_WC` + the `mister,map-writecombine` property parse in `uio_pdrv_genirq` |
| `linux.config` | `CONFIG_UIO=y`, `CONFIG_UIO_PDRV_GENIRQ=y`, `CONFIG_CMDLINE="uio_pdrv_genirq.of_id=generic-uio"` + `CONFIG_CMDLINE_EXTEND=y` |
| `rootfs-overlay/etc/udev/rules.d/65-mister-uio.rules` | the `/dev/mister/*` symlinks; `scripts/ci-tests.sh` checks it names exactly the DT's UIO nodes |

**Naming: one name per device.** The UIO name is `mister_<name>`; udev adds `/dev/mister/<name>`
with `_` as `-`. IRQ nodes are `mister_f2h_irq<N>`, N the hardware f2h line, at
`/dev/mister/irq/f2h-irq<N>`. Semantic names are udev aliases only, never second UIO names:
`/dev/mister/doorbell/<k>` and `/dev/mister/fb` (§5). 0072 replaced the beta-only
`0043-dts-uio-doorbells` and `0044-dts-uio-fpga-regions` and renamed their nodes to this scheme
(`mister_doorbell<k>` is now `mister_f2h_irq<k+7>`, `mister_lw_window` is `mister_lw_bridge`);
greenfield's consumers move to the same names. The target is the MiSTer kernel fork (`scripts/export-kernel-tree.sh`);
mainline would want a real binding and driver instead of `generic-uio`, which is out of scope.

**Stock Main_MiSTer is unaffected.** It maps everything through `/dev/mem`, which these nodes do not
touch. The reserved-memory tiles lie outside `memblock.memory` under `mem=511M`, so ARM's
`pfn_valid()` (`arch/arm/mm/init.c:126-145`, which tests `memblock.memory`, not `no-map`) and
therefore every `/dev/mem` page attribute are what they were. **Greenfield is not unaffected:** the
UIO names changed (§2.3), so it needs its matching rename (branch `lead/uio-names`) to land with
this series.

## 1. The tree

```
/reserved-memory                      no-map tiles, 0x1ff00000..0x3fffffff, no overlap
    mister-ddr-low@1ff00000           0x000ff000   DDR above mem=511M (A2065 window et al.)
    mister-handoff@1ffff000           0x00001000   U-Boot handoff / reboot-flag page
    mister-scaler@20000000            0x01800000   ascal scaler, 3 slots
    mister-core@21800000              0x00800000   core-owned
    mister-fb@22000000                0x01800000   HPS framebuffer   <- MiSTer_fb memory-region
    mister-core@23800000              0x1c800000   core-owned, to the top of the aperture
    (RT line only: ramoops@1fe00000, patch 0046)
/MiSTer_fb@22000000                   + memory-region = <&mister_fb_mem>
/mister                               simple-mfd, ranges
    lw-bridge@ff200000                mister_lw_bridge      SO, never WC        H-1
    h2f-bridge@c0000000               mister_h2f_bridge     SO                  H-1, whole window
    fpga-mgr@ff706000                 mister_fpga_mgr       SO                  GPO +0x10, GPI +0x14
    ddr-aperture@20000000             mister_ddr_aperture   WC (with 0045)
    ddr-low@1ff00000                  mister_ddr_low        SO, two maps
    fabric-irqs                       simple-mfd, interrupt-parent = <&intc>
        f2h-irq1 .. f2h-irq63         mister_f2h_irq1 .. mister_f2h_irq63
```

0072 appends a second `/ { ... };` block at the end of the DTS instead of editing nodes in place.
dtc merges it into `/reserved-memory` and `MiSTer_fb@22000000`, so the patch applies with or
without the RT line's ramoops node (0046) and whatever size `MiSTer_fb`'s own `reg` has.

`/mister` and `fabric-irqs` are `simple-mfd`, not `simple-bus`: the IRQ nodes carry no `reg`, which
dtc's `simple_bus_reg` check flags under `W=1`, and `simple-mfd` is populated by
`of_platform_default_populate()` the same way. The group sits at the root, not under
`soc/bus@ff200000` (`&fpga`), which belongs to the FPGA image's own overlay. Overlapping `reg`
between the two is no conflict: neither the bus nor `uio_pdrv_genirq` requests its region.

## 2. Evidence, per node

Evidence rows are from `Main_SiSTer/rewrite-plan/phase5/ddr-region-map.md` (§2, §4, §5),
`Main_SiSTer/docs/layers/mmio-windows.md` and `Main_SiSTer/docs/layers/doorbell-axi-rt.md` §1/§8,
re-read at the sources they cite. Legacy = `Main_MiSTer_master`; core RTL = the published
`sys/` template, quoted from `NES_MiSTer/sys/` (identical lines in every core the map lists).

### 2.1 Reserved memory

| tile | base | size | evidence / arithmetic |
|---|---|---|---|
| ddr-low | `0x1ff00000` | `0xff000` | `mem=511M` = `0x1ff00000` is the kernel's top (`board/mister/de10nano/uboot.env:80,99`). The minimig A2065 flat window is `0x1ff00000` + 64 KiB (`support/minimig/minimig_a2065_ddr3.h:17`); the tile runs to the handoff page. |
| handoff | `0x1ffff000` | `0x1000` | legacy `fpga_io.cpp:398,601` `shmem_map(0x1FFFF000, 0x1000)`; U-Boot `fpgaload` clears it (`uboot.env:92`). |
| scaler (shared) | `0x20000000` | `0x1800000` | `sys_top.v:716-721` `RAMBASE 0x20000000`, `RAMSIZE 0x800000` (`0x200000` under `MISTER_SMALL_VBUF`, SNES); ascal triple-buffers at `base + b*RAMSIZE` (`ascal.vhd:436-443`): 3 x 8 MiB = 24 MiB. Shared: stock SNES (`MISTER_SMALL_VBUF`, 6 MiB of slots) starts its MSU data track at `0x20600000`, inside this tile. |
| core (lo) | `0x21800000` | `0x800000` | the gap between the scaler's end and the framebuffer; core-owned (SNES MSU, Jaguar, ...). |
| fb (shared) | `0x22000000` | `0x1800000` | `MiSTer_fb@22000000` (`0004`); legacy `video.cpp:37` `FB_ADDR = 0x20000000 + 32 MiB` and `:2414` maps `FB_SIZE*4*3` = 1920*1080*12 = `0x17BB000`, rounded up to 24 MiB, below the Menu core's wipe at `0x24000000`. Shared: stock SNES resumes its MSU track at `0x22800000`, past the 8 MiB hole (`Main_SiSTer/rewrite-plan/phase5/ddr-region-map.md:212`; legacy `user_io.cpp:2882-2888`). Its upper 16 MiB is shared too: the SPARCstation 20 boot PROM `0x22f00000-0x22f7ffff` and RAM from `0x23000000` live there (`Main_SiSTer/rewrite-plan/phase5/ddr-region-map.md:120,124,246,275`), as do, on stock, the SNES/SGB MSU track and legacy's `video_menu_bg` buffers `0x227e9000-0x237bafff` (`:239`); greenfield and the fb mode clear stay below `0x22800000`. |
| core (hi) | `0x23800000` | `0x1c800000` | the rest: `0x40000000 - 0x23800000`. |

The tiles sum to `0x00100000 + 0x20000000` exactly (`0xff000 + 0x1000 + 0x1800000 + 0x800000 +
0x1800000 + 0x1c800000`) and are adjacent, `0x1ff00000` to `0x40000000`. They must not overlap: `of_reserved_mem` reports overlap as an error.

**Why carve-outs at all:** `memory@0` declares 1 GiB and only U-Boot's `mem=511M`, which this repo
does not own, kept the kernel out of the aperture. Lose that token and a write-combined user mapping
of the aperture would alias pages the kernel maps cacheable, which ARMv7 leaves UNPREDICTABLE.
With `no-map` the DTB alone keeps the kernel out.

**"Shared" tiles are reserved from the kernel, not from cores.** Greenfield moves the SNES MSU
track above the fb tile (its `parity-divergences.md` row, branch `lead/snes-msu-base`); stock keeps it
inside both tiles.

**The framebuffer tile is 24 MiB and matches 0071's `reg`** (`0x22000000 + 0x1800000`, PR #297).
The driver reads its `reg`, not the `memory-region` (`MiSTer_fb.c` is untouched here), so until 0071
lands the 8 MiB stock `reg` simply sits inside the tile. Merge order between the two is free.

### 2.2 The `/mister` windows

| node | base | size | attribute | evidence |
|---|---|---|---|---|
| lw-bridge | `0xff200000` | `0x200000` | SO | U-Boot `base_addr_ac5.h:45` `SOCFPGA_LWFPGASLAVES_ADDRESS`; mainline `socfpga.dtsi` `fpga: bus@ff200000`; greenfield `kLwBridgeBase`/`kLwBridgeSize` (`hal/axi.h`) |
| h2f-bridge | `0xc0000000` | `0x3c000000` | SO | U-Boot `base_addr_ac5.h:9` `SOCFPGA_FPGA_SLAVES_ADDRESS 0xc0000000`; the window ends at the STM, `:10` `0xfc000000`: `0xfc000000 - 0xc0000000 = 0x3c000000` (960 MiB) |
| fpga-mgr | `0xff706000` | `0x1000` | SO | legacy `fpga_base_addr_ac5.h:49`; GPO at `+0x10`, GPI at `+0x14` (`fpga_manager.h:17-18`); mmio-windows rows 1-2 |
| ddr-aperture | `0x20000000` | `0x20000000` | WC with 0045, else SO | greenfield `fpga_mem(x) = 0x20000000 \| (x & 0x1FFFFFFF)`; mmio-windows row 9; the f2sdram ports |
| ddr-low | `0x1ff00000` / `0x1ffff000` | `0xff000` / `0x1000` | SO | as the two tiles above; map0 / map1 |

**H-1 (LW and h2f).** An access to an offset no fabric slave decodes never completes: the SoC
hard-hangs with no fault, no panic, no console output, power cycle only. Seen three times on
silicon, all reads; a write also waits for a fabric response, so presume it equally lethal. The
menu core decodes nothing in the LW window. **On the h2f window it is the whole window:** every
core checkout on this host (48 `sys/sysmem.sv` copies) instantiates `cyclonev_hps_interface_hps2fpga`
with only `port_size_config` and no slave (`NES_MiSTer/sys/sysmem.sv:398-402`), so no offset answers (`port_size_config` `2'b11` in every copy). The node is kept as a root-only
H-1 trap, describing the hardware, not as a usable window. Mapping is safe; touching is not. A consumer
touches only offsets the loaded core declares; "probe to see what answers" is destructive,
diagnostics included. No signal is ever delivered, so a SIGBUS guard cannot help.

**Never write-combine LW or h2f.** WC is Normal memory, which ARMv7 may read speculatively; a WC
mapping of an H-1 window could hang the SoC off a mispredicted path with no program access at all.
That is why `mister,map-writecombine` is per node and the aperture is a node of its own.

**fpga-mgr is shared with the kernel's `fpgamgr0`** (`altr,socfpga-fpga-mgr`,
`CONFIG_FPGA_MGR_SOCFPGA=y`), which claims the page. That driver touches it only for an `fpga_mgr`
write, and Main programs the FPGA itself, so this is the same sharing `/dev/mem` has always had.
`uio_pdrv_genirq` does not request the region, so the two do not collide at probe.

**Bridges are not enabled from the DT.** U-Boot's `fpgaload` runs `bridge enable`
(`uboot.env:92`) and Main's bridge sequencer owns the enable order (mmio-windows §1, rows 4-7);
`fpga_bridge0..2` stay as `0004` left them, with no `bridge-enable` property.

### 2.3 Fabric-to-HPS interrupts

`sys_top.v:573-576`: `wire [63:0] f2h_irq = {video_sync,HDMI_TX_VS};` into
`cyclonev_hps_interface_interrupts .irq(f2h_irq)`. Line N of that vector (N = 0..63; Quartus'
`f2h_irq0[31:0]` is N = 0..31, `f2h_irq1[31:0]` is N = 32..63) is GIC SPI cell `40 + N`, i.e.
cells 40..103. The cell is the SPI index, not the INTID (INTID = cell + 32). The existing
`MiSTer_fb` node uses the same convention: cell 40 = `HDMI_TX_VS`.

| N | cell | node / uio name | trigger | evidence |
|---|---|---|---|---|
| 0 | 40 | none (MiSTer_fb) | edge (fb driver) | `HDMI_TX_VS`, owned by `MiSTer_fb` (`0004`); the only f2h line a kernel driver claims in either DTB |
| 1 | 41 | `f2h-irq1` / `mister_f2h_irq1` | EDGE_RISING | `video_sync` (`sys_top.v:1532-1542`): high for one line at the sync line, a pulse with no ack register; measured 60.17 Hz on silicon |
| 2..7 | 42..47 | `f2h-irq2..7` / `mister_f2h_irq2..7` | LEVEL_HIGH | tied 0 in every published core; platform reserve (audio watermark, CEC) per the allocation policy |
| 8..15 | 48..55 | `f2h-irq8..15` / `mister_f2h_irq8..15` (doorbell pool, `/dev/mister/doorbell/1..8`) | LEVEL_HIGH | the doorbell pool; `TurboGrafx16_MiSTer/sys/mister_cd_ring.v:158` `doorbell ... level, LEVEL_HIGH -> f2h_irq[8]` |
| 16..63 | 56..103 | `f2h-irq16..63` / `mister_f2h_irq16..63` | LEVEL_HIGH | tied 0 in every published core |

**Trigger types follow the fabric.** A doorbell is backed by a cause register the FPGA holds high
until userspace acknowledges it; edge would lose a second event raised before the first is acked,
level cannot. `video_sync` is a pulse, so edge. Lines no core drives take the doorbell convention,
and a core that drives one must follow it.

**Lines nobody drives never fire, and no line can storm.** `uio_pdrv_genirq_handler()` calls
`disable_irq_nosync()` on every interrupt and only `irqcontrol(1)` (userspace writing a 1 to
`/dev/uioN`) re-enables it (`drivers/uio/uio_pdrv_genirq.c`); for level lines the probe sets
`IRQ_DISABLE_UNLAZY`, so the line is truly masked while the cause is cleared. A line a buggy core
holds high fires once and stays masked until someone re-arms it. Measured: pool nodes on undriven
lines recorded zero events and zero initial count across 42 s of armed polling (the 0043 rig run).
`f2h-irq1` is edge-triggered, so its disable is lazy: the first `video_sync` edge fires the handler
and is masked, the second only sets `IRQS_PENDING` and masks the line at the GIC, and that edge is
replayed on the first arm. With no consumer it costs two interrupts per boot (`/proc/interrupts`
shows 2, the UIO event count 1), and **the first armed `read()` returns a stale vsync: discard the
first event after arming** (§5).

**One IRQ thread per node.** UIO requests each line with `request_threaded_irq()`, so every node
has an `irq/NN-mister_f2h_irqN` kthread at `SCHED_FIFO` 50; on the RT kernel forced threading
roughly doubles that, to about 126 threads. They sleep unless their line fires and cost about
1-1.5 MB in all; on 6.18 they are new. Their affinity must keep them off the RT CPU (CPU 1) (§6).

**Each claim is exclusive.** `uio_pdrv_genirq` refuses `IRQF_SHARED`, so a node takes its line from
any future in-kernel consumer; such a consumer deletes that one node.

**Why line 0 has no node.** `MiSTer_fb` requests it with `IRQF_SHARED` (`MiSTer_fb.c:357`) while
`uio_pdrv_genirq` requests without it, so whichever probes second fails to get the line; and even
if both held it, the UIO handler masks the line on every fire until userspace re-arms it, which
would starve the framebuffer's vsync.

**Doorbell aliases.** Pool ordinal k (1..8) is f2h line k+7, SPI cell k+47: greenfield's
`l1_proto/include/proto/irq_binding.h:14` (an `IRQ:` token's ordinal N names doorbell N) and
`docs/layers/doorbell-axi-rt.md:26,31` (the pool is SPI 48..55, doorbells 1..8 in order);
`TurboGrafx16_MiSTer/sys/sys_top.v:590-591` (f2h_irq[8] = `mister_doorbell1`). udev links
`/dev/mister/doorbell/<k>` to `irq/f2h-irq<k+7>`; `ci-tests.sh` checks all eight.

## 3. Left out, and why

- **Line 0** (`HDMI_TX_VS`): `MiSTer_fb`'s vsync; a UIO node would fail to share it or starve it (§2.3).
- **Per-core regions** (MSU track, savestates, rewind rings, CD buffers, ...). Cores change without
  kernel updates; per-core layouts stay in greenfield's manifests (`CoreWindowDecl`) as offsets into
  `mister_ddr_aperture`. The DT carries only the board-level tiles every core shares.
- **FPGA-to-HPS DMA request lines**: they need a dmaengine binding and no core uses them. A future
  fb/DRM driver gets mem-to-mem DMA from the existing `pdma` node (`pl330`) with no DT change; the
  request lines matter only if fabric logic paces the transfers.
- **The FPGA-manager data port** (`0xffb90000`), **SDRAM controller** (`0xffc20000`), **reset
  manager** (`0xffd05000`), **system manager** (`0xffd08000`), **NIC-301** (`0xff800000`): owned by
  kernel drivers (fpga-mgr, sdr, reset, syscon) or tied to the frozen bridge sequence; whether those
  jobs move to kernel frameworks is an on-device evaluation (doorbell-axi-rt.md §4), not a DT edit.
  Main keeps `/dev/mem` for them.
- **ramoops** (`0046`): RT line only; it needs `CONFIG_PSTORE*`, which the 6.18 line does not set.

## 4. Kernel side

- `uio_pdrv_genirq` has an empty `of_match_table` filled from its `of_id` parameter; built in, the
  kernel command line is the only way to set it. `CONFIG_CMDLINE_EXTEND` appends
  `CONFIG_CMDLINE` after U-Boot's `/chosen` bootargs (`drivers/of/fdt.c`), so `root=`, `mem=511M` and
  the rest survive. Never `CMDLINE_FORCE`: it overwrites them and the board does not boot. If
  `u-boot.txt`'s `$v` contains `--`, or the line exceeds `COMMAND_LINE_SIZE` (1024), the appended
  `of_id` token is silently lost (passed to init, or truncated): the board boots, but no UIO node
  binds.
- `linux,uio-name` gives the exported name verbatim (`uio_pdrv_genirq.c`), so node names follow DT
  convention while userspace keeps its names.
- **Write-combining is a two-part unlock.** Stock `uio_mmap_physical()` maps `UIO_MEM_PHYS` with
  `pgprot_noncached()` (Strongly-ordered on ARMv7: ~100 MB/s write, ~54 MB/s read into the aperture,
  measured). 0045 adds `UIO_MEM_PHYS_WC` (`pgprot_writecombine()`, Normal non-cacheable) and the
  property parse. Without 0045 the property is ignored and the aperture maps SO: slower, never
  unsafe. It never degrades to a cached mapping, which would corrupt memory the FPGA writes without
  snooping the A9 caches. `/dev/mem` cannot give WC at `0x20000000` and above: for `!pfn_valid`
  ranges ARM's `phys_mem_access_prot()` returns `pgprot_noncached()` whatever the flags. Below it
  the reverse holds: `pfn_valid()` rounds to the 4 MiB pageblock `[0x1fc00000, 0x20000000)`
  (`arch/arm/mm/init.c:126-145`), so the ddr-low and handoff tiles are `pfn_valid`, and `/dev/mem`
  with `O_SYNC` maps them WC while their UIO node maps them SO.

## 5. Userspace: how to map each node

1. Find the node by name: scan `/sys/class/uio/uio*/name`, or open `/dev/mister/<name>` from the udev
   rule. Never key on the `uioN` minor; adding a node renumbers every minor after it.
2. Read `/sys/class/uio/uioN/maps/mapM/{addr,size,offset}`.
3. `mmap(NULL, len, PROT_READ|PROT_WRITE, MAP_SHARED, fd, M * getpagesize())`. The offset selects
   the map; every map is mapped from its base, so reaching offset X needs `len >= X + n` (VA only:
   the mappings are `VM_PFNMAP`, cost no RAM and are not page-locked by `mlockall`).
   - **MAP_SHARED only.** UIO does not check the flags; a `MAP_PRIVATE` mapping copies the page on
     the first write and every later store lands in anonymous RAM the FPGA never sees, while
     read-back through the same mapping still passes.
   - `mister_ddr_low`: map0 = `0x1ff00000` (A2065 window at +0), map1 = the handoff page.
4. On the WC aperture a store is not visible when it retires: fence (`dmb`/`dsb`) between the payload
   and whatever publishes it (doorbell, strobe, ring index).
5. Interrupts: `write(fd, &(uint32_t){1}, 4)` arms the line, a blocking `read(fd, &count, 4)` returns
   the event count when it fires; clear the core's cause register, then arm again. Discard the
   first event after the first arm: an edge line (`f2h-irq1`) replays an edge latched while it was
   masked, and a level line may report one raised before its consumer started.

`/dev/mister/` view (eudev, `65-mister-uio.rules`): `lw-bridge`, `h2f-bridge`, `fpga-mgr`,
`ddr-aperture`, `ddr-low`, `irq/f2h-irq1` .. `irq/f2h-irq63`, and two alias sets:
`doorbell/1` .. `doorbell/8` (= `irq/f2h-irq8` .. `irq/f2h-irq15`) and `fb` (the `MiSTer_fb`
framebuffer, matched by its `fix.id`; `/dev/fb0` itself is unchanged). Nodes stay root-only (0600);
a non-root Main would add a group to the rule.

## 6. Verified, and what only the rig can show

Verified off-device (2026-11-13): both lines apply the full series at `-F0` (6.18.63, 7.3.4), with
and without the `MiSTer_fb` 24 MiB resize; the DTB builds with 0 dtc warnings by default and the
same 5 pre-existing `socfpga.dtsi` warnings under `W=1` as before; the decompiled DTB has 68 unique
UIO names, SPI cells 40..103 each exactly once, and the merged `/reserved-memory`, whose `mister-*`
tiles are adjacent from `0x1ff00000` to `0x40000000`; `drivers/uio/`
compiles with 0045 under both resolved configs; the RT resolved config is unchanged and the 6.18 one
gains exactly the UIO and cmdline symbols. QEMU has no Cyclone V machine, so probing is rig-only:

- all 68 UIO devices probe on both kernels, with the names above, and `/dev/mister/*` (doorbell
  and fb aliases included) appears;
- `/proc/cmdline` ends in `uio_pdrv_genirq.of_id=generic-uio` with U-Boot's tokens intact;
- `dmesg` lists the six reserved tiles, no overlap error, and `/proc/iomem` is unchanged below
  `0x1ff00000`;
- `f2h-irq1` shows 2 in `/proc/interrupts` and 1 UIO event, then stays masked; lines 2..63 record
  none;
- no `irq/NN-mister_*` thread has CPU 1 in its affinity (`/proc/irq/NN/smp_affinity_list`,
  `taskset -p` on the kthreads), on both kernels;
- stock Main behaves as before; greenfield works only with its `lead/uio-names` rename (it then
  resolves `mister_fpga_mgr` through UIO on both lines, still SO);
- the aperture's WC throughput on the 6.18 line.
