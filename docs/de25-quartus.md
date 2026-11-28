# DE25-Nano: Quartus for a core developer

**What this is.** What you need to compile anything for the DE25-Nano's FPGA, and the one rule
that has no DE10 equivalent: a core loads only on a board whose flash holds the matching base.
**Status 2026-11-28.** The policy in §5 is [ADR 0036](decisions/0036-de25-scope-and-base-generations.md)
(Proposed).

**Evidence tags:** **[V]** verified here (a build, a file, or #318's bench); **[P]** read in a
vendor page or a vendor-published file; **[S]** search-snippet grade (Altera's page refused a
direct fetch, so only the indexed text was read); **[U]** unknown.

## 1. Which Quartus

**Quartus Prime Pro. There is no alternative.**

| | DE10-Nano (Cyclone V) | DE25-Nano (Agilex 5 E-series, `A5EB013`) |
|---|---|---|
| Edition | Lite or Standard | **Pro only** **[S]** |
| Licence | none | free, but required (§3) |
| Version | 17.0.2 by convention | one exact build, enforced by the chip (§5) |
| Hosts | Windows, Linux | Windows, Linux; no macOS |

Lite and Standard also have releases numbered 25.1. They are a different product for the older
families and cannot target Agilex 5 **[S: [migration guide](https://intel.com/content/www/us/en/docs/programmable/787947/24-3/overview-23962.html)]**.
#318's bench used **Pro** 25.1.1 Build 125.

Pro's synthesis is stricter than 17.0's, and Cyclone V megafunctions (`altpll` and the like)
have no Agilex form: they become Agilex IP. A DE10 core needs source work to port, not only a
recompile **[U: no core has been ported here]**.

## 2. The words

| Term | Meaning |
|---|---|
| SDM | a small processor inside the chip. It boots first, and only from the QSPI flash |
| `.sof` | what a Quartus compile produces |
| `quartus_pfg` | splits a `.sof` into the two halves below, and prints their hashes (`-i`) |
| phase-1 (`.jic` for the flash, or `hps.rbf`) | SDM firmware + the HPS pin and DDR setup ("HPIO") + the SPL. No fabric logic |
| `core.rbf` | SDM firmware + the FPGA pin setup ("IO") + the logic ("CORE") |
| HPS IO hash | a fingerprint of the HPS pin and DDR setup. The SDM refuses a `core.rbf` whose hash differs from the running phase-1's (`0xf0040000`) |
| base generation | one phase-1 and the rule for building cores that match it (§5) |

The section layout is in Altera's own published pair: `quartus_pfg -i` lists CMF, HPIO and HPS
sections for `ghrd.hps.rbf`, and CMF, IO and CORE sections plus a separate "IO hash" for
`ghrd.core.rbf` **[P]**. Each core carries its own FPGA pin setup, so cores may use FPGA pins
differently. Only the HPS side must match.

## 3. The licences: two, both free

| Licence | Feature | Without it |
|---|---|---|
| Agilex 5 E-series (`SW-AGILEX-5E`) | `quartus_agilex5e` | synthesis stops: `Error (19286): No license for family Agilex 5` **[V]** |
| Nios V | `6AF7_D036`, `6AF8_D036` | synthesis and fit pass, then the assembler refuses to write a `.sof`: `Error (23714)`, "Unlicensed IP: Nios V/m" **[V 2026-11-28]** |

The second one is needed because Altera's baseline design contains a Nios V/m (§5). Our own base
may drop that processor later, and the Nios V licence with it; today both are needed.

- **Where.** Altera's Self-Service Licensing Center, signed in with a free account. The Agilex 5
  one can also be requested from inside Quartus (Tools > License Setup) **[P: [how-to](https://www.macnica.co.jp/en/business/semiconductor/articles/altera/145133/)]**.
- **Type FIXED, bound to one NIC ID.** Each licence names the network address of one computer.
- **One year.** Both expire a year after issue, and Quartus stops at expiry. Request them again.
  A licence covers every Pro version released before its maintenance end, so a renewed licence
  still runs the pinned, older build **[P]**.
- **`LM_LICENSE_FILE`** takes a colon-separated list, one path per licence file.

**Rules.**

- **Your own NIC ID.** Request the licences for the address of your own machine, or one you
  choose for your own container. There is no shared default: a file issued for a well-known
  address works on any machine, and a FIXED licence is for one.
- **Never share or commit a `.dat`.** `.gitignore` does not protect you from `git add -f`.
- **A CI runner has its own licences,** in its owner's name ([ADR 0036](decisions/0036-de25-scope-and-base-generations.md) D6).

## 4. The toolchain as this tree runs it

Two containers exist. Neither is redistributable by us; each user builds or pulls their own.

| Image | Quartus | From | Used for |
|---|---|---|---|
| `de25/quartus-pro:26.3.0.114-agilex5` | Pro 26.3.0 Build 114 | built locally by `fpga/de25-base/tools/quartus-image.sh` | **the candidate base generation 1** (§5) |
| `alterafpga/quartus-pro:25.3.1-patch1.02-agilex5` | Pro 25.3.1 Build 100, patch 1.02 | Altera, Docker Hub (17.5 GB) | the first base recipe on Terasic's GHRD ([`de25-base-image.md`](de25-base-image.md) §1–§5); not the base any more |

**Building the 26.3 image.** Altera has published no 26.3 container. `tools/quartus-image.sh
<dir>` builds one from Altera's four installer files, downloaded while signed in:
`QuartusProSetup-26.3.0.114-linux.run`, `QuartusProSetup-part2-26.3.0.114.qdz`,
`agilex_common-26.3.0.114.qdz` and `agilex5-26.3.0.114.qdz` (16 GB). It checks their SHA-1s
against `tools/quartus-26.3.0.114.sha1` (Altera's published values), installs Quartus with
Agilex 5 only into a container laid out like Altera's images, and tags it (55 GB on disk).
Running it accepts Altera's EULA. **[V 2026-11-28: built; `quartus_sh --version` reports 26.3.0
Build 114.]** Keep the four installer files: a frozen version is only as durable as your copy
of its installer.

**Running a command.** `fpga/de25-base/tools/quartus-run.sh COMMAND…` runs it in the container
with the current directory at `/w`:

```
QUARTUS_IMAGE=de25/quartus-pro:26.3.0.114-agilex5 \
QUARTUS_LICENSE=<your .dat> QUARTUS_MAC=<the NIC ID it was issued for> \
    fpga/de25-base/tools/quartus-run.sh quartus_sh --version
```

`QUARTUS_MAC` is required with a licence and has no default. `QUARTUS_LICENSE` takes one file or
a colon-separated list (paths without spaces); each is mounted read-only and listed in
`LM_LICENSE_FILE` **[V 2026-11-28: both licences, 26.3 container]**.

The wrapper makes four changes, all needed **[V 2026-11-25, on this tree's build host]**:

- **A stub `libudev.so.1` mounted over the image's** (`tools/udev-stub.c`, built on first use
  into `.quartus-run/`). Without it, `quartus_syn` aborts with `realloc(): invalid pointer` in
  `udev_enumerate_scan_devices`. The caller is FlexLM's host-ID probe, which `dlopen`s libudev,
  so every compile hits it. Preloading the real library only moves the crash. The stub's
  `udev_new()` returns NULL, the probe skips its device scan, and the NIC-based licence still
  matches.
- **`--mac-address "$QUARTUS_MAC"`.** The licence is bound to a NIC ID, and a container gets a
  new address each run.
- **The caller's uid,** so the outputs are not owned by root.
- **`HOME=/tmp`,** because that uid has no home directory in the image.

The stub makes udev report no devices, so the wrapper is for compiling only. `quartus_pgm`
through it would find no USB-Blaster. Altera's own instructions for its images use the host's
network (`--net=host`) and `LM_LICENSE_FILE` instead **[P: [Docker Hub](https://hub.docker.com/r/alterafpga/quartus-pro)]**;
that also works with a licence issued for the host's own NIC.

## 5. The version freeze: base generations

**On the DE10 the Quartus version is a convention.** A core built with another version still
loads. **On the DE25 it is a binary interface,** enforced by the SDM: a core loads only over a
phase-1 with the same HPS IO hash, and that hash moves with the base design **and** with the
Quartus version (#318: the same project gave a different hash under 26.3 than under 25.1.1).
Altera's rule for this boot mode on the sibling families is the same: both halves from one
Quartus version, patches included **[S: [KB 000074153](https://www.intel.com/content/www/us/en/support/programmable/articles/000074153.html), [KB 348443](https://community.altera.com/kb/knowledge-base/why-does-configuration-fail-when-phase-1-and-phase-2-configuration-files-come-fr/348443)]**.

So the project names **base generations**. A generation is a triple:

| Part | Candidate generation 1 |
|---|---|
| Quartus build, patch level included | Prime Pro **26.3.0 Build 114**, no patches (`de25/quartus-pro:26.3.0.114-agilex5`) |
| Base design | Altera's `terasic-de25-nano-devkit/baseline-a55`, tag **`QPDS26.3_REL_BASELINE_PR`** (commit `8d88fc5`) |
| HPS IO hash | `DF9589F2122209AF6D453BEE8BA0DD18F3192FA556B0B6E245CD3CB1A8FE4B1F` |

It is a **candidate** until hash test 2 passes:

| Test | What | Result |
|---|---|---|
| 1 | the unmodified baseline, compiled in our container, reproduces Altera's published hashes | **pass [V 2026-11-28]**: HPS IO hash `DF9589F2…` and IO hash `9E82C9A17CF700A994EBE01D191137F59C3CDDB4CA0B7615D929EC4FBFD1DD7D`, both identical to Altera's `ghrd.core.rbf`. Timing met (worst setup slack 3.113 ns, TNS 0) |
| 2 | the baseline plus `de25_hdmi`, and a third design with clearly different fabric, keep the HPS IO hash and load over one phase-1 | **not run** |

Test 1's steps, for anyone reproducing it:

```
quartus_ipgenerate --synthesis=verilog …      # regenerate the IP
quartus_sh --flow compile top -c baseline_a55
quartus_asm …                                  # the .qsf sets FLOW_DISABLE_ASSEMBLER ON
quartus_pfg -c baseline_a55.sof baseline_a55.core.rbf -o hps=ON -o hps_core_only=ON
quartus_pfg -i baseline_a55.core.rbf           # prints both hashes
```

Our core came out at 1,822,720 B against Altera's 1,855,488 B: we skipped the Nios V firmware
hex, which is RAM contents and part of neither hash.

**Why test 2 matters.** Every core loaded on a DE25 so far was split from the same `.sof` as
its phase-1 (#318). Altera documents ways two *different* designs on one Quartus version end up
with different HPS IO hashes **[S: [HPS IO hash compatibility](https://www.intel.com/content/www/us/en/docs/programmable/813762/25-3/hps-io-hash-compatibility.html), [troubleshooting](https://www.intel.com/content/www/us/en/docs/programmable/813762/25-3/hps-io-hash-mismatch-troubleshooting.html)]**:
the hash covers the HPS memory bank (3A with one HPS memory interface) and any IP in it, and it
moves with pin locations, unconstrained pins, register packing, and the clock-spine value on
PLL tie-off logic in that bank.

## 6. What a core build must do

Planned, with the core template ([`de25-nano-tasks.md`](de25-nano-tasks.md) D2.14):

1. **Build with the generation's exact Quartus build.** Not a newer patch level.
2. **Keep the HPS side byte-for-byte:** the HPS and memory-interface IP settings, and every pin
   and I/O standard in the HPS bank(s), come from the template and are never edited per core.
3. **Constrain what the fitter may move:** a `CLOCK_SPINE` assignment for every PLL in an HPS IO
   bank, and no unconstrained pins (`PROMOTE_WARNING_TO_ERROR 12677`, as Altera's baseline does).
4. **Check the hash and fail closed.** The build runs `quartus_pfg -i` on its `core.rbf` and
   stops if the HPS IO hash is not the generation's.
5. **Publish a manifest with the core:** generation, HPS IO hash, Quartus build, SHA-256. The
   loader and U-Boot refuse a mismatch with a readable message
   ([`de25-fabric-interface.md`](de25-fabric-interface.md) §4).

## 7. When the version must change

Plan on a new Quartus version meaning a new generation: new phase-1, every core rebuilt.

| Option | What it costs |
|---|---|
| **Stay frozen** (the default, for years) | depends on Altera still issuing the free licences and on our copies of the installers; no fixes for the device from later versions |
| **Two phase-1 images in the flash** (RSU slots; a phase-1 is under 1 MiB) | switching generation is a reboot, so old cores keep working while cores are rebuilt. Needs ADR 0035 gate B5 **[U]** |
| **A flag day** | the flash is rewritten and every core re-released at once; old cores stop loading |

## 8. Open

| Item | Settles it |
|---|---|
| Hash test 2 | the owner's bench ([`de25-nano-tasks.md`](de25-nano-tasks.md)) |
| Whether 26.3 lists `A5EB013BB23` under *final* device support | the 26.3 release notes (683706), read in a browser |
| Whether the user LEDs sit in the HPS bank (the baseline's `.qsf` puts them on a 1.1 V bank) | the device pin-out |
| The Quartus licence's clause on distributing output files | the licence text inside the installed Quartus (ADR 0035 gate B7) |
