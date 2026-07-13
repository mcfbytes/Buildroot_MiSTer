# ADR 0003 — xone / Xbox Wireless Dongle firmware (`xow_dongle.bin`)

**Status:** Accepted (2026-07-13) — decided by @mcfbytes. This ADR number was
reserved during P0 (`docs/stock-inventory/firmware.md:103`, TASKS.md P3.2) for
exactly this decision; it went through a full options writeup before the
maintainer ruled, so both the ruling and the rejected alternatives are
recorded below.
**Impact:** P3.2 (this task) — `package/xone/`, `package/xow-firmware/`,
`package/cabextract/`; `configs/mister_de10nano_defconfig`; image size and
the built rootfs's `/lib/firmware/` contents.
**Supersedes:** nothing. First ruling on this question.

## The question

Xbox One/Series controllers connect to a PC (or MiSTer) two ways: wired USB,
or through the **Xbox Wireless Dongle**, a proprietary MT7612U-based USB
radio. The dongle ships with no onboard firmware — the host must upload
`xow_dongle.bin` (70,620 bytes) to it after every power-up before it does
anything. Without that file, the dongle enumerates on USB but no wireless
controller pairing works at all.

**Stock bundles this file.** `docs/stock-inventory/firmware.md:103,107` — it
is present at `/usr/lib/firmware/xow_dongle.bin` in the stock image, baked
directly into `linux.img`, not fetched on demand. There is no stock
"on-device fetch" behavior to reproduce; parity means the built image must
contain the file.

**The file's provenance is the open question.** `xow_dongle.bin` is not
free-software firmware with its own release/license the way, say, RTL8188EU's
`rtlwifi/*.bin` blobs are (Realtek ships those under a permissive firmware
redistribution license, mainline `linux-firmware.git` carries them). It is
extracted from Microsoft's own Windows driver package for the Xbox Wireless
Adapter — that is how the `xow` and `xone` upstream projects themselves
obtain it (see "Provenance," below) — and Microsoft's driver downloads are
covered by [Microsoft's Terms of
Use](https://www.microsoft.com/en-us/legal/terms-of-use), not by a
redistribution license comparable to GPL/MIT/the Linux firmware-redistribution
statement. Whether bundling that firmware inside a third-party Linux
distribution image is authorized under those terms is **not spelled out
anywhere Microsoft publishes**, and this project has no standing to resolve
that ambiguity by itself — hence the ADR, not a silent choice made mid-patch.

## Provenance (checked directly, not assumed)

Both live upstream forks solve "get the firmware" the same way, and neither
vendors the blob in their own git history:

- **`medusalix/xow`** (the original project this all traces back to) and
  **`medusalix/xone`**'s `install/firmware.sh` / the newer
  **`dlundqvist/xone`**'s `install/firmware.sh` (the fork this project
  packages — see `package/xone/xone.mk`) both download a small set of
  Microsoft driver `.cab` files directly from
  `catalog.s.download.windowsupdate.com` / `download.windowsupdate.com` (a
  public Microsoft CDN, no authentication), extract one firmware member from
  each with `cabextract`/`bsdtar`, verify its sha256 against a hash the
  script itself hardcodes, and install it under `/lib/firmware/`.
- `dlundqvist/xone`'s script prints, before downloading: *"The firmware for
  the wireless dongle is subject to Microsoft's Terms of Use:
  https://www.microsoft.com/en-us/legal/terms-of-use"* and requires an
  Enter keypress to continue (or `--skip-disclaimer` for scripted installs).
  That disclaimer is the clearest signal available of how upstream itself
  reads the legal situation: **acknowledged as Microsoft's IP, distributed by
  fetching from Microsoft directly rather than by the *xone* project
  redistributing its own copy.**
- Verified live at pin time (2026-07-13): the exact `.cab` this ADR's decision
  uses —
  `http://download.windowsupdate.com/c/msdownload/update/driver/drvs/2017/07/1cd6a87c-623f-4407-a52d-c31be49e925c_e19f60808bdcbfbd3c3df6be3e71ffc52e43261e.cab`
  — returns HTTP 200, `Content-Type: application/vnd.ms-cab-compressed`,
  199,891 bytes, sha256
  `65736a84ff4036645b8f8ec602bed91ab6353019c9cb3233decab9feec0f6f04`.
  Extracting it (`cabextract`) yields `FW_ACC_00U.bin`, 70,620 bytes, sha256
  `48084d9fa53b9bb04358f3bb127b7495dc8f7bb0b3ca1437bd24ef2b6eabdf66` — **the
  size matches `docs/stock-inventory/firmware.md`'s documented stock
  `xow_dongle.bin` size exactly**, and the hash matches `dlundqvist/xone`'s
  own `install/firmware.sh` manifest for USB PID `0x02fe`. (Not independently
  diffed against a byte-copy of the real stock blob — none was available in
  this environment — but the size match plus matching a second independent
  upstream project's own pinned hash for the same Microsoft file is strong
  corroboration, not proof of byte-identity to the specific copy stock's 2016
  build captured.)

## Options weighed

**(a) Bundle the blob directly in this repo's git history.** Rejected
outright, independent of the licensing question: G6 ("no binaries in git,
ever") is a standing rule in this project, not a case-by-case judgment call,
and it applies with extra force to a license-ambiguous proprietary blob —
committing it would make every future clone of this repository a
redistribution event with no way to later "un-ship" it (git history is
forever). Never seriously on the table.

**(b) Zero-redistribution: first-boot / user-run fetch from the user's own
already-licensed Windows driver install (the original `xow` `get_firmware.sh`
model — extract from a driver package the user personally downloaded after
accepting Microsoft's terms on their own machine).** The cleanest legal
posture of the three: MiSTer never touches Microsoft's CDN or redistributes
anything — the user's own act of installing the Windows driver is what
accepts Microsoft's terms, and MiSTer merely reads a file already on that
user's disk. Rejected here not on legal grounds but on **usability**: it
requires the user to own a Windows machine, install Microsoft's driver on it,
locate the extracted firmware, and transfer it to the MiSTer SD card by hand
— a far worse experience than stock's "it just works," and not something a
typical MiSTer user (many of whom have no Windows machine at all) can be
expected to do. Kept as the documented fallback (see "Consequences," below)
for anyone who would rather not accept option (c)'s risk.

**(c) — DECIDED. Redistribute for parity, sourced fresh from Microsoft's own
official driver package at BUILD TIME, hash-pinned, never committed to
git.** Ship `/lib/firmware/xow_dongle.bin` in the built image (parity with
stock), but produce that file by having the **Buildroot build itself**
download the same Microsoft `.cab` the `xow`/`xone` projects' own installers
use, extract the firmware with a from-source-built `cabextract`, verify its
hash, and install it — every time the image is built, from Microsoft's live
CDN, never from a copy this repository stores. This is not a new
redistribution channel this project invented: it is the `xow`/`xone`
projects' own documented, public installation mechanism, automated as a
hash-verified Buildroot package instead of a shell script the user runs by
hand. See "Mechanism" below.

## Decision

**(c).** Parity wins, on the strength that this project is automating an
already-public, already-used distribution mechanism (Microsoft's own CDN,
the same one `xow`/`xone` point users at today) rather than inventing a new
one, combined with hash-pinning giving byte-for-byte auditability of exactly
what gets shipped.

**The residual risk is real and is being accepted, not resolved.** Whoever
ships the image this build produces to an end user is, at that point,
redistributing a file whose license terms are Microsoft's Terms of Use, not
a redistribution license — no different in kind from what stock's own 5.15
fork has done since 2016 (stock bakes the same file into `linux.img`), but
also not *legally cleared* by that precedent; MiSTer's stock distribution has
never had this scrutinized by Microsoft or by counsel either. **Fetching
fresh from Microsoft at build time instead of committing a copy to git
narrows the risk surface (no permanent git-history redistribution, always the
current Microsoft-published bytes, trivially removable by disabling
`BR2_PACKAGE_XOW_FIRMWARE`) but does not eliminate it.** If this is ever
challenged, "we automated the same fetch xow/xone's own installer does,
hash-verified, never vendored" is a materially better position than "we
committed a copy of Microsoft's binary to our repository," but it is a better
position, not a cleared one.

## Mechanism

Three new packages, wired together (`configs/mister_de10nano_defconfig`
enables both leaf packages; `package/cabextract/` is a build-time-only host
tool with no `Config.in`, pulled in automatically):

1. **`package/cabextract/`** — `host-cabextract`, built from cabextract.org.uk's
   own upstream source (v1.11, GPL-3.0+, hash-pinned), the same author/site
   as this tree's existing `libmspack` package. HOST-only: nothing on the
   target ever runs it.
2. **`package/xow-firmware/`** (`BR2_PACKAGE_XOW_FIRMWARE`, `depends on
   BR2_PACKAGE_XONE`, `default y`) — downloads the Microsoft `.cab` above
   (hash-pinned in `xow-firmware.hash`), runs `cabextract` on it, asserts the
   extracted `FW_ACC_00U.bin`'s sha256 inline (a **second**, independent hash
   gate beyond the outer `.cab` download — Buildroot's `.hash`-file mechanism
   only covers the downloaded source, not a file this package's own build
   step derives from it), then installs it to the target as:
   The driver actually packaged here (`dlundqvist/xone` — see
     `package/xone/xone.mk` for why that fork was chosen over the older
     `medusalix/xone`) does **not** use stock's single fixed firmware name.
     Stock's fork hardcoded the one shared name `xow_dongle.bin` regardless of
     dongle USB PID; `dlundqvist/xone` moved to a **per-PID scheme**,
     requesting `xone_dongle_%04x.bin` at runtime
     (`transport/dongle.c:xone_dongle_fw_load`), and its `id_table` binds
     **four** dongle PIDs. Those four split cleanly into two kinds:
   - **Two EXTERNAL USB adapters** — the only ones that can physically plug
     into a DE10-Nano, so both are shipped, each with **its own distinct
     firmware** (they are genuinely different blobs from different Microsoft
     `.cab`s, *not* one blob under two names, so neither can be an alias of
     the other):
     - `0x02fe` — the newer "Xbox Wireless Adapter for Windows" ("S"
       revision). Its firmware (70,620 bytes) installs as
       `/lib/firmware/xow_dongle.bin` (**stock's literal filename**, for
       byte-for-byte parity, `docs/stock-inventory/firmware.md`) with
       `xone_dongle_02fe.bin` a symlink to it (same bytes → no duplicate copy).
       Shipping only the stock-parity name would satisfy a literal file diff
       but leave the driver unable to find its firmware
       (`request_firmware()` fails), so both names must resolve to it.
     - `0x02e6` — the original 2015 Xbox One Wireless Adapter (model 1713),
       cheaper and very common on the used market. Its firmware is a
       **different** 70,008-byte blob from a **different** `.cab` (2017/03,
       hash-pinned via `XOW_FIRMWARE_EXTRA_DOWNLOADS`), installed as a real
       file `/lib/firmware/xone_dongle_02e6.bin` — **not** a symlink to
       `xow_dongle.bin` (that would load the wrong firmware onto the old
       adapter). Without it, an owner of the original adapter hits `Direct
       firmware load for xone_dongle_02e6.bin failed with error -2` and a dead
       dongle.
   - **Two BUILT-IN modules — deliberately NOT shipped.** `0x02f9` (ASUS,
     Lenovo) and `0x091e` (Surface Book 2) are, per the driver's own
     `id_table` comments, wireless modules **soldered into those laptops'
     mainboards** — not USB devices, physically incapable of attaching to a
     DE10-Nano. Their firmware (`FW_ACC_CL.bin` / `FW_ACC_BR.bin`, from yet
     other `.cab`s) would be dead weight for hardware that cannot exist on
     this platform, so it is intentionally omitted. (This corrects an earlier
     draft that mislabeled these two as "China/Brazil regional variants" —
     they are laptop-internal modules, not regional SKUs.)
3. **`package/xone/`** — the driver itself (unambiguously GPL-2.0-or-later,
   no open question at all — see `package/xone/xone.mk` for the fork-choice
   writeup and 6.18 build notes). Builds and functions independent of
   whether `xow-firmware` is enabled; only wireless-dongle pairing needs the
   firmware. Wired controllers, headsets, and the chatpad need no firmware.

## Verification (executed, not asserted)

- `make xow-firmware` (fresh `dl/`/`output/build/`): downloads **both** `.cab`s
  (0x02fe source + 0x02e6 `EXTRA_DOWNLOADS`), Buildroot's own hash check passes
  on each (`... .cab: OK`), `cabextract` extracts each `FW_ACC_00U.bin` into a
  separate subdir (they collide on member name), both inline `sha256sum -c`
  assertions pass, and — confirmed in the built `rootfs.tar`, not just
  `output/target` — the image gets `/lib/firmware/xow_dongle.bin` (70,620 bytes,
  `48084d9f...`), the `xone_dongle_02fe.bin` symlink to it, and
  `xone_dongle_02e6.bin` as a real 70,008-byte file (`080ce409...`).
- **Both hash gates independently proven to hard-fail on tampering, then
  restored:** corrupting the `.cab`'s pinned hash in `xow-firmware.hash`
  produces Buildroot's standard `ERROR: ... wrong sha256 hash ... Incomplete
  download, or man-in-the-middle (MITM) attack`, build exit 2; separately,
  corrupting the *extracted-firmware* hash assertion in the `.mk` produces
  `FW_ACC_00U.bin: FAILED` / `sha256sum: WARNING: 1 computed checksum did NOT
  match`, also exit 2. Both restored to the correct pinned values and
  reverified clean afterward.
- `BR2_PACKAGE_XOW_FIRMWARE` can be turned off independently of
  `BR2_PACKAGE_XONE` (it only `depends on` xone, doesn't force it) — anyone
  who prefers option (b) can disable it and populate
  `/lib/firmware/xow_dongle.bin` themselves via an overlay.

## Consequences

- **This ADR does not need revisiting if Microsoft changes or removes this
  CDN URL** — the build will simply fail loudly (404, or a hash mismatch if
  they republish under the same URL with different bytes) rather than
  silently shipping something wrong; a future contributor would re-derive the
  current URL from `dlundqvist/xone`'s own `install/firmware.sh` (the
  manifest this pin was cross-checked against) the same way this ADR did.
- **Not a substitute for real legal review before any public release (P4).**
  This is the maintainer's own risk call for personal/local use, explicitly
  not a "this is cleared" determination — flagged the same way ADR 0010
  flags its own n=1 evidence limitation.
- If Microsoft's terms are ever read as prohibiting this, the fallback is
  option (b) (already designed, just not wired as the default) or option
  (c-minus): disable `BR2_PACKAGE_XOW_FIRMWARE`, document that wireless Xbox
  needs the user to supply `/lib/firmware/xow_dongle.bin` themselves. No code
  changes needed to fall back — just flipping the one Kconfig option and
  writing the equivalent user-facing instructions in
  `docs/stock-inventory/README.md`-adjacent user docs (not yet written; not
  this task's scope).
- **Controller/dongle function is unverified without hardware** (P3.13,
  same caveat as `package/xone/xone.mk`'s driver notes) — this ADR proves the
  firmware lands in the image with the right bytes and the right names for
  the driver to find; it does not prove a real dongle pairs and streams
  input.
