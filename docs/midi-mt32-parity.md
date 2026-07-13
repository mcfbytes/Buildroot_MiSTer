# MIDI / MT-32 parity — stock vs. ours

Task: **P3.8**. Depends on P2.1 (full package set). Consumed by P3.13 ([HW]
confirmation of the ALSA MIDI device list).

**Status: authored, not build-verified.** This task's worktree ships no
`output/` tree (author-only constraint) — every package below was written
against upstream source read directly from GitHub and cross-checked against
`docs/stock-inventory/`, but has not itself been run through `make`. The
"Verify-in-build checklist" section at the end lists exactly what the
orchestrator's shared build + P3.13's hardware pass need to confirm.

## 1. Stock's MIDI/MT-32 stack, traced to source

`docs/stock-inventory/binaries-needed-full.txt` (P0.3) lists five MIDI-related
`usr/{bin,sbin}` binaries in stock's rootfs:

| Path | Links against | Role |
|---|---|---|
| `usr/bin/amidi`, `usr/bin/aplaymidi`, `usr/bin/arecordmidi`, `usr/bin/aseqdump`, `usr/bin/aseqnet`, `usr/bin/aserver`, `usr/bin/aconnect` | `libasound.so.2` (+ libc/libm/libpthread/libdl) | alsa-utils' MIDI/sequencer CLI tools |
| `usr/sbin/fluidsynth` | `libfluidsynth.so.3`, libc, libpthread | FluidSynth's own CLI |
| `usr/sbin/midilink` | `libasound.so.2`, libc, libm, libpthread | **the actual ALSA-sequencer client** cores talk to |
| `usr/sbin/mlinkutil` | `libasound.so.2`, libc, libm, libpthread | MidiLink's small companion utility |
| `usr/sbin/mt32d` | `libasound.so.2`, libc, libgcc_s, libm, libpthread, libstdc++ (no `libmt32emu.so`) | munt's console MT-32/CM-32 emulator daemon |

None of `midilink`/`mlinkutil`/`mt32d` were previously traced to an upstream
project in this repo's docs. Traced here (web search + `gh api` against the
actual source, not guessed):

- **`midilink`/`mlinkutil`** are built from **MiSTer-devel/MidiLink_MiSTer**
  (GPL-3.0+), the official MiSTer-devel daemon that bridges ALSA-sequencer USB
  MIDI adapters, MUNT, FluidSynth, and a UDP/TCP network peer to the
  Minimig/ao486/etc. cores. Its upstream `Makefile` builds exactly these two
  binaries from `main.c modem.c serial.c serial2.c misc.c udpsock.c tcpsock.c
  alsa.c ini.c directory.c modem_snd.c` (→ `midilink`) and `mlinkutil.c
  misc.c serial2.c tcpsock.c` (→ `mlinkutil`).
- **`mt32d`** is upstream **munt**'s (LGPL-2.1+) own `mt32emu_alsadrv` console
  daemon (`mt32emu_alsadrv/src/console.cpp` + `alsadrv.cpp` + `wav.cpp`,
  linked against `libmt32emu` + `libasound`). Confirmed, not inferred: reading
  MidiLink's own `main.c`, `start_munt()` does
  `system("taskset %d mt32d %s -f %s &", MUNTCPUMask, MUNTOptions, MUNTRomPath)`
  — MidiLink shells out to a bare `mt32d` on `$PATH`, exactly matching stock's
  separate `usr/sbin/mt32d` binary and explaining why it has no
  `libmt32emu.so` `DT_NEEDED` entry of its own (mt32d links `libmt32emu`
  itself, not the other way around — `midilink` doesn't link it at all).
- **`fluidsynth`** — analogous: `main.c`'s `start_fsynth()` does
  `system("taskset %d fluidsynth -is -a alsa -m alsa_seq %s &", FSYNTHCPUMask, fsynthSoundFont)`.

**Correction flagged for `docs/package-manifest.md` (P0.7), not made there
(out of this task's lane):** that doc's §2 table says MIDI/MT-32 support has
"none [init script] — driven directly by the `MiSTer` binary, not a daemon."
That undersells it — `midilink` **is** a daemon (no init script starts it;
it's launched on demand by the closed-source `MiSTer` binary / menu when a
core requests MIDI, which is consistent with "not an S-script service" but
not with "not a daemon" once running). The ROM/soundfont **data** conclusion
in that same doc (§2 note and §4 gap-table row) — that `mt32-rom-data/` and
`soundfonts/` are FAT-partition asset files, not a rootfs package concern —
is independently correct and unaffected by this; see §3 below.

## 2. The munt decision

Buildroot 2026.02.3 has no `munt` package (`work/buildroot/package/munt` does
not exist). Since stock ships MT-32 emulation via `mt32d`, this task authors
**`package/munt/`**:

- **Source:** `github.com/munt/munt`, tag `munt_2_8_2` (resolves to commit
  `3b05ec276f9e605af86b0eaef7f5eda43477a31f`, checked at pin time).
- **Builds:** `libmt32emu` (the emulation library) via munt's own CMake
  project, restricted to the `mt32emu/` subdirectory (`MUNT_SUBDIR = mt32emu`)
  so the Qt-based `mt32emu_qt` GUI and `mt32emu_win32drv` are never even
  configured. Then `mt32d` is hand-compiled in a
  `MUNT_POST_INSTALL_TARGET_HOOKS` step from
  `mt32emu_alsadrv/src/{console,alsadrv,wav}.cpp` against the freshly staged
  `libmt32emu` + this system's `alsa-lib` — matching upstream's own
  `mt32emu_alsadrv/Makefile` `mt32d` target (`-lmt32emu -lm -lasound
  -lpthread`, no X11). `xmt32` (the X11 GUI sibling in the same source
  directory, needs `libX11`/`libXt`/`libXpm`) is deliberately never built:
  this is a headless image, and MidiLink's "MUNT" uartmode only ever spawns
  `mt32d`.
- **License:** LGPL-2.1+ for both the library and `mt32d` itself (checked:
  `mt32emu_alsadrv/src/console.cpp`'s own file header independently declares
  LGPL-2.1+, not just the generic `COPYING.LESSER.txt` split).
- **Why `mt32emu_alsadrv` needed a hand-rolled build instead of
  `cmake-package` alone:** it is a legacy plain-`Makefile`-only module the
  top-level `CMakeLists.txt` doesn't even list as a configurable option
  (checked: only `munt_WITH_MT32EMU_SMF2WAV` / `_QT` / `_WIN32DRV` exist
  there).

### ROM note (G6 — no binaries in git)

The actual Roland `MT32_CONTROL.ROM` / `MT32_PCM.ROM` (and CM-32L
equivalents) are Roland's copyrighted firmware. **Stock does not bundle
them** (confirmed: `docs/stock-inventory/` has no ROM entries anywhere, and
`mt32emu_alsadrv/README.txt` itself says "A copy of the MT32_PCM.ROM file
(not provided)"). This package does not fetch, extract, or embed them
either. `mt32d` takes the ROM directory as a `-f <path>` command-line
argument at **runtime** — MidiLink passes stock's default of
`/media/fat/linux/mt32-rom-data` (per `MidiLink.INI`'s `MUNT_ROM_PATH`,
matching `docs/package-manifest.md`'s existing `mt32-rom-data/` finding).
Users who own real MT-32/CM-32 hardware dump and supply their own ROM files
at that path on the FAT partition, exactly as in stock — nothing on the
Linux rootfs side changes this contract.

### Soundfont note

Same shape, already settled by P0.7 and unchanged by this task:
`docs/package-manifest.md` §2/§4 already correctly classifies `soundfonts/`
as a FAT-partition asset (`files/linux/`), not a rootfs package concern.
MidiLink's own README documents the configured path as
`MidiLink.INI`'s `FSYNTH_SOUNDFONT` key (seen pointing at either
`/media/fat/SOUNDFONT/default.sf2` or `/media/fat/linux/SOUNDFONT/sc-55.sf2`
in different upstream doc revisions — both are FAT-partition user/asset
paths, not a rootfs concern either way). **Deliberately not added:**
Buildroot's own `BR2_PACKAGE_FLUID_SOUNDFONT` (ships `FluidR3_GM.sf2`, MIT
licensed, ~140 MiB unpacked) — stock does not ship a soundfont on the Linux
rootfs at all, so adding one here would be new scope beyond parity, a size
regression against the ≥15%-free budget (PLAN §11/P2.7), and not what this
task was asked to do.

## 3. FluidSynth parity

Already present before this task (`BR2_PACKAGE_FLUIDSYNTH=y` +
`BR2_PACKAGE_FLUIDSYNTH_ALSA_LIB=y`, `work/buildroot/package/fluidsynth/`
pins `FLUIDSYNTH_VERSION = 2.4.7`). No version or config change needed here;
confirmed compatible:

- `docs/package-manifest.md` line 133/448 already records
  `libfluidsynth.so.3` (major version 3, matching stock's
  `usr/lib/libfluidsynth.so.3.0.0`) at `2.4.7`.
- The ALSA-seq backend (`-Denable-alsa=1`, gated by
  `BR2_PACKAGE_FLUIDSYNTH_ALSA_LIB`) is what MidiLink's `start_fsynth()`
  needs (`fluidsynth -a alsa -m alsa_seq`) — already selected.

**One path difference, not fixed here:** Buildroot's `fluidsynth.mk` has no
override of `FLUIDSYNTH_INSTALL_TARGET_CMDS`, so the CLI binary lands
wherever the project's own CMake install rules put it (`usr/bin/fluidsynth`,
Buildroot's default), not stock's `usr/sbin/fluidsynth`. This does not break
anything: MidiLink's `start_fsynth()` spawns a bare `fluidsynth` via
`system()`, resolved through `$PATH`, not an absolute path (checked, same as
the `mt32d` call) — and both `/usr/bin` and `/usr/sbin` are on this image's
`$PATH` for the same user context MidiLink itself runs as. Flagged as a
BUILD-verify item below rather than "fixed" because forcing FluidSynth's
install path away from Buildroot's own package convention is a bigger
change than this task's scope warrants for a difference with no observed
behavioral consequence.

## 4. ALSA-seq kernel config — already at parity, no change made

Checked against `board/mister/de10nano/linux.config` (this task's worktree)
and a prior full build's resolved `.config` (from a sibling build tree, read
for verification only, not modified): `CONFIG_SND_SEQUENCER=y` is already
set, and the kernel's own Kconfig `select` chain resolves everything else
automatically, with no explicit symbol needed in the board fragment:

- `CONFIG_SND_SEQUENCER` (`sound/core/seq/Kconfig`) → `select SND_TIMER`,
  `select SND_SEQ_DEVICE`.
- `CONFIG_SND_USB_AUDIO=y` (already set, for USB audio interfaces generally)
  → `select SND_RAWMIDI` (`sound/usb/Kconfig`).
- `CONFIG_SND_SEQ_MIDI` (`sound/core/seq/Kconfig`) is `def_tristate
  SND_RAWMIDI` — it tracks `SND_RAWMIDI`'s value automatically, so it
  resolves to `=y` for free once `SND_RAWMIDI` does.

The prior build's resolved `.config` confirms the full chain actually
resolves as expected: `CONFIG_SND_TIMER=y`, `CONFIG_SND_SEQ_DEVICE=y`,
`CONFIG_SND_RAWMIDI=y`, `CONFIG_SND_SEQUENCER=y`,
`CONFIG_SND_SEQUENCER_OSS=y`, `CONFIG_SND_SEQ_MIDI_EVENT=y`,
`CONFIG_SND_SEQ_MIDI=y` — a line-for-line match against
`docs/stock-inventory/stock-linux.config`'s own `CONFIG_SND_*` block
(including both being built-in `=y`, not modules — so there is no
`snd-seq`/`snd-seq-midi` module-autoload concern to wire up; it's always
present). `CONFIG_SND_VIRMIDI` is `# not set` in both stock and ours too
(exact match). **No `board/mister/de10nano/linux.config` edit made — none
needed.**

## 5. alsa-utils — MIDI subset added, general subset flagged as a gap

`BR2_PACKAGE_ALSA_UTILS` was **not enabled at all** before this task (a real
gap: none of stock's `amidi`/`aplaymidi`/`arecordmidi`/`aseqdump`/
`aseqnet`/`aconnect`/`alsactl`/`alsamixer`/`aplay`/`arecord`/`amixer`/etc.
existed in the defconfig). This task enables the **MIDI-specific** subset
only, matching P3.8's scope and its "ALSA MIDI device list matches stock"
done-when criterion:

```
BR2_PACKAGE_ALSA_UTILS=y
BR2_PACKAGE_ALSA_UTILS_ACONNECT=y
BR2_PACKAGE_ALSA_UTILS_AMIDI=y
BR2_PACKAGE_ALSA_UTILS_APLAYMIDI=y
BR2_PACKAGE_ALSA_UTILS_ARECORDMIDI=y
BR2_PACKAGE_ALSA_UTILS_ASEQDUMP=y
BR2_PACKAGE_ALSA_UTILS_ASEQNET=y
```

**Flagged, not fixed here (out of P3.8's scope):** stock's general
(non-MIDI) alsa-utils tools — `alsactl`, `alsamixer`, `aplay`/`arecord`
(`APLAY`), `amixer`, `alsatplg`, `alsaucm`, `alsaloop`, `alsabat`
(`BAT`), `iecset`, `speaker-test` — are present in stock
(`docs/stock-inventory/binaries-needed-full.txt`) but are general ALSA
audio parity, not MIDI parity. No Phase-3 task in `TASKS.md` currently
appears to own this gap explicitly (`P2.1`, which applied P0.7's package
list, is marked done `[x]` without them); whoever owns general ALSA
userland parity should pick this up. **A genuine gap in this Buildroot
version regardless of scope:** stock's `usr/bin/aserver` has **no**
corresponding suboption in `work/buildroot/package/alsa-utils/
alsa-utils.mk` at all — every other stock alsa-utils binary maps to a
`BR2_PACKAGE_ALSA_UTILS_*` build target except this one. `aserver` is
`aseqnet`'s companion network sequencer-bridge daemon; niche (not used by
any MiSTer core), so this is noted rather than worked around (e.g. by
hand-adding a custom install rule) for this task.

## 6. Files changed by this task

- `package/munt/{Config.in,munt.mk,munt.hash}` — new.
- `package/midilink/{Config.in,midilink.mk,midilink.hash}` — new.
- `Config.in` (repo root) — added a `"MIDI / MT-32 (P3.8)"` menu sourcing
  both new packages' `Config.in`.
- `configs/mister_de10nano_defconfig` — added `BR2_PACKAGE_MUNT=y`,
  `BR2_PACKAGE_MIDILINK=y`, `BR2_PACKAGE_ALSA_UTILS=y` + six MIDI-specific
  `BR2_PACKAGE_ALSA_UTILS_*` suboptions, right after the existing FluidSynth
  block.
- `board/mister/de10nano/linux.config` — **not changed** (§4: already at
  parity).
- `external.mk` — **not changed** (already globs `package/*/*.mk`; no
  per-package wiring needed there).
- This doc.

## 7. Verify-in-build checklist (for the orchestrator's shared build + P3.13 [HW])

1. **`package/munt` actually compiles.** Biggest real uncertainty in this
   task: `mt32emu_alsadrv/src/{console,alsadrv,wav}.cpp` is old
   (copyright-header dates 2003–2019) C++ that has, as far as this task
   could determine, never been built against a current C++17/20-default
   GCC, nor verified against `munt_2_8_2`'s *current* `mt32emu.h` C++ API
   (the module is tagged together with the core library in the same repo
   release, which is a reasonable signal they're kept in sync, but this was
   not independently confirmed by an actual compile — this worktree has no
   `output/` tree to compile in). If the build fails on strict C++
   standard-conformance, the fix is almost certainly adding a `-std=gnu++`
   flag to `MUNT_BUILD_MT32D` in `package/munt/munt.mk`, not a deeper
   problem — but confirm rather than assume.
2. **`mt32d` and `midilink`/`mlinkutil` land at the paths stock uses**
   (`/usr/sbin/mt32d`, `/usr/sbin/midilink`, `/usr/sbin/mlinkutil`) and are
   executable.
3. **ALSA MIDI device list matches stock** (this task's actual done-when,
   [HW] in P3.13): boot the image, run `aconnect -l` / `amidi -l`, confirm
   the same client shape stock produces — MidiLink registering its own
   client plus, when a core requests it, `mt32d`'s ports 128:0/128:1 (per
   `mt32emu_alsadrv/README.txt`) or `fluidsynth`'s ALSA-seq port.
4. **`mt32d` end-to-end with real ROMs**, on hardware, with user-supplied
   `MT32_CONTROL.ROM`/`MT32_PCM.ROM` at `/media/fat/linux/mt32-rom-data`
   (this task cannot verify this at all — no ROMs are or should be present
   anywhere in this repo or its build).
5. **`fluidsynth`'s installed path** (§3) — confirm `$PATH` for the context
   MidiLink actually runs under covers `/usr/bin` (Buildroot's install
   location), not just `/usr/sbin` (stock's).
6. **`aserver`'s absence** (§5) does not block anything MiSTer actually
   uses — confirm no core/script invokes it.

## 8. Uncertainties

- **Whether stock's `mt32d`/`midilink`/`mlinkutil` are *exactly* the
  binaries this task's pinned commits would reproduce is not verified.**
  `docs/stock-inventory/` has no build-provenance data for these three
  binaries (no version string extraction, no `strings`/build-ID capture) —
  this task's source attribution is a best-effort trace from binary name +
  linked-library shape + the projects' own public documentation
  (`mt32emu_alsadrv/README.txt`'s port numbers 128:0/128:1, MidiLink's own
  README describing exactly this `mt32d`-spawning behavior), not a byte-for-
  byte confirmation against stock's actual shipped binaries. `strings
  usr/sbin/mt32d` / `usr/sbin/midilink` against the extracted stock image
  (available at whatever path P0.3's `work/extracted/` used) would
  meaningfully strengthen this if someone wants to re-check.
- **Fork choice for MidiLink**, MiSTer-devel's official repo vs.
  `bbond007/MiSTer_MidiLink`: picked the official repo on the reasoning that
  no evidence surfaced of the two `midilink`/`mlinkutil` sources
  meaningfully diverging (both describe themselves identically), and this
  task builds `mt32d` from munt's own upstream source rather than
  bbond007's bundled build scaffold, so that fork's main draw doesn't apply
  here. Not exhaustively diffed against the fork.
- **`docs/package-manifest.md`'s MIDI/MT-32 characterization** (§1 above) is
  flagged as incomplete, not corrected — that file is out of this task's
  lane. If whoever owns P0.7 wants to update it, this doc is the citation.
