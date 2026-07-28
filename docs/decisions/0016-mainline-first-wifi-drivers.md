# ADR 0016 — Mainline-first WiFi drivers (retire out-of-tree forks where 6.18 covers the chip)

**Status:** Accepted (2026-07-13) — decided by @mcfbytes, hardware-verified
**Impact:** P3.1 (WiFi kernel-module packages), P3.3 (firmware), P3.4 (WiFi
userland / `interfaces`). Changes which driver binds each USB WiFi dongle and
narrows the committed out-of-tree set. Ships in the "v9" image.
**Supersedes:** the P3.1 premise that *all six* stock out-of-tree Realtek forks
are re-sourced and built (recorded in `docs/wifi-parity.md`,
`docs/kernel-config-deltas.md`, `docs/package-manifest.md`, and
`scripts/inventory/build_modules.py`, all annotated to point here).

> **Update (v10.2, 2026-07-27) — the rule below is still unchanged; the
> exception list is no longer empty. It has exactly one entry: RTL8852CU.**
> The v10 note immediately below emptied the list because mainline had caught
> up on every chip then in it. That was a statement about *those chips*, not a
> new policy of "zero out-of-tree drivers" — and the exhaustive v10.1 USB audit
> (`docs/wifi-parity.md` §7) then found one chip mainline has *not* caught up
> on. `rtw89` carries the RTL8852C chip HAL (`rtw8852c.c`, `rtw8852c_rfk.c`,
> `rtw8852c_table.c`) but its only bus file for that HAL is the PCIe one:
> `rtw8852ce.c` exists, **`rtw8852cu.c` does not**, and the only Kconfig symbol
> offered is `RTW89_8852CE`, which `depends on PCI`
> (`drivers/net/wireless/realtek/rtw89/Kconfig:113-122`). This board has no
> PCIe, so even that is unreachable. An RTL8852CU / RTL8832CU Wi-Fi 6E dongle
> therefore had **no driver at all**, which is precisely the condition under
> which this ADR permits a fork. `BR2_PACKAGE_RTL8852CU_MORROWNR=y` is
> accordingly selected in the defconfig
> (`package/rtl8852cu-morrownr/`, pinned at morrownr/rtl8852cu-20251113
> `1530c38e`). Verified on the pinned 6.18.40 tree, not assumed; note the same
> rtw89 directory *does* ship `rtw8851bu.c` and `rtw8852bu.c`, so this is an
> 8852C-specific gap rather than rtw89 lacking USB support.
>
> Bind-conflict check (the reason this ADR disables rather than merely
> un-selects redundant forks): **none**. The fork's tree is multi-chip, but
> upstream enables only `CONFIG_RTL8852C` and the USB ID table is
> `#ifdef`-partitioned per chip, so the built module claims nine IDs
> (`0bda:c85a/c832/c85d`, `0db0:991d`, `2c4e:0127`, `3574:6251`, `35b2:0502`,
> `35bc:0101`, `35bc:0102`); all nine grep clean against
> `drivers/net/wireless/` and `drivers/bluetooth/` in 6.18.40. The blocks that
> are compiled *out* would collide (8852B ↔ `rtw89_8852bu`, 8851B ↔
> `rtw89_8851bu` and `mt7921u`), so the chip switches must stay as upstream
> ships them.
>
> Costs accepted with it: upstream declares 6.18 only "community supported"
> (its README tests 5.15–6.14 against Realtek), the driver needs a `KSRC=`
> build-time override to compile under Buildroot at all, and its firmware is
> linked in as a ~15 MB C array rather than loaded from `/lib/firmware`, so the
> `.ko` is large (1.8 MB as shipped, `.ko.xz`). All three are documented with
> file:line evidence in `package/rtl8852cu-morrownr/rtl8852cu-morrownr.mk`.
> Consequence line below updated: 6 → 0 → **1**.
>
> **A FOURTH cost, found only by actually compiling it (2026-07-27): the
> driver does not build for 32-bit ARM as shipped.** When this package was
> added it had never been compiled — the `KSRC=` finding above was a
> well-evidenced prediction from reading the Makefile, not an observed build.
> The first real `make all` got every object through cleanly and then died at
> modpost:
>
> ```
> ERROR: modpost: "__aeabi_uldivmod" [8852cu.ko] undefined!
> ```
>
> `c2h_wicense_rpt_info()` (`phl/hal_g6/mac/mac_ax/fwcmd.c:2147-2148`) divides a
> `u64` by 1000 with plain `/`. No 32-bit architecture can lower that inline, so
> gcc emits an EABI helper call the kernel does not export to modules. Invisible
> upstream, whose README tests x86_64 and aarch64 — where the same expression is
> a native instruction. Fixed by
> `package/rtl8852cu-morrownr/0001-mac_ax-use-div_u64-for-64-bit-division-on-32-bit-arch.patch`,
> which swaps in the kernel's portable `div_u64()`; the affected code is a
> debug-telemetry printer, so behavioural risk is nil. Verified by a full
> `dirclean` + rebuild, so the patch is applied by Buildroot rather than by hand.
> **The maintenance consequence is the real cost:** every version bump must
> re-check this, and a bump that silently drops it fails the build closed (the
> patch stops applying) — which is the loud failure we want, but it is now a
> standing task on this package that its mainline-driven siblings do not carry.

> **Update (v10) — the rule below is unchanged; its exception list is now
> empty.** This ADR kept three morrownr forks on the sole factual ground that
> mainline had no USB driver for those chips. Two of those three facts have
> since expired: the shared `rtw88_88xxa` core (`RTW88_88XXA`) landed upstream
> in **6.13**, *after* this ADR was written, giving mainline `rtw88_8812au`
> (RTL8812AU) and `rtw88_8821au` (RTL8811AU/RTL8821AU); `rtw88_8814au`
> (RTL8814AU) landed in 6.16 and was adopted earlier. Applying this ADR's own
> rule to the new facts, **`BR2_PACKAGE_RTL8812AU` and
> `BR2_PACKAGE_RTL8821AU_MORROWNR` are now deselected too** — so ~~the image
> carries **zero** out-of-tree WiFi drivers~~ (**superseded in v10.2** — exactly
> one, `rtl8852cu-morrownr`; see the note above), down from the "6 → 3" recorded
> under Consequences below. Device coverage was diffed per USB ID and nothing
> is lost (the forks' extra IDs all belong to other chips whose in-kernel
> drivers this image already builds). Worked diff, and the v10 additions of
> `brcmfmac` + MT7663U/ar3k firmware, in `docs/wifi-parity.md` §6.
> The packages stay sourced in `package/` as a one-line revert.

## The problem

MiSTer's 5.15 stock kernel predates mainline USB support for several Realtek
WiFi chips, so stock carried six out-of-tree vendor forks (8188eu, rtl8188fu,
8812au, 8821au, 8821cu, 88x2bu). P3.1 faithfully re-sourced all six as
hash-pinned Buildroot `kernel-module` packages. But our kernel is **6.18**, and
in the intervening years mainline gained in-kernel drivers for most of those
chips. Continuing to ship the out-of-tree forks then means:

- **Maintenance burden** — vendor forks need per-kernel-version compat patches and
  are unmaintained/abandoned over time.
- **Bind conflicts** — if both an out-of-tree fork and the in-kernel driver claim
  the same USB ID, whichever loads first wins non-deterministically.
- **Worse standards support** — the out-of-tree 88x2bu advertised SAE+CMAC but
  **failed WPA3-only association** (`status_code=1`) on the user's RTL8822BU.
  Mainline `rtw88_8822bu` goes through `mac80211`, so WPA3/SAE/PMF work correctly
  (verified on hardware: auto-connects to a WPA3-only 5 GHz network at boot).

## Decision

**Use the in-kernel driver for every chip 6.18 can drive; keep an out-of-tree
fork only where mainline still has no USB driver.**

| Stock out-of-tree | 6.18 replacement | Out-of-tree package |
|---|---|---|
| 8188eu, 8188fu, (8710bu) | `rtl8xxxu` (`CONFIG_RTL8XXXU=m`) | **disabled** |
| 8821cu / 8811cu | `rtw88_8821cu` | **disabled** |
| 8822bu | `rtw88_8822bu` (HW-verified WPA3) | **disabled** |
| 8812au (RTL8812AU, 11ac) | none in mainline *(v10: `rtw88_8812au`, 6.13)* | ~~kept~~ → **disabled in v10** — `package/rtl8812au` (morrownr) |
| 8821au (RTL8811AU/8821AU, 11ac) | none in mainline *(v10: `rtw88_8821au`, 6.13)* | ~~kept~~ → **disabled in v10** — `package/rtl8821au-morrownr` |
| 8814au (RTL8814AU, 4×4 11ac) | none in mainline *(later: `rtw88_8814au`, 6.16)* | ~~added~~ → **disabled** — `package/rtl8814au-morrownr` |
| *(not in stock)* 8852cu (RTL8852CU/8832CU, Wi-Fi 6E) | **none in mainline** — `rtw89` is PCIe-only for 8852C | **added and ENABLED in v10.2** — `package/rtl8852cu-morrownr` |

The disabled packages stay **present and sourced** in the tree (selectable in
menuconfig) as a one-line-revert fallback; they are just not selected in the
defconfig. Disabling (not deleting) is deliberate: if a mainline driver ever
disappoints on specific hardware, flipping the defconfig symbol restores the
fork without re-vendoring.

### Broadened mainline coverage (beyond stock parity)

Since we are on mainline anyway, enable the in-kernel USB WiFi drivers stock
never had, each with matching `linux-firmware`:

- `rtw88_8822cu`; `rtw89` Wi-Fi 6/6E USB — `RTL8851BU`/`RTL8852BU`
- MediaTek `mt7921u` / `mt7925u` (Wi-Fi 6/6E)
- Atheros `ath9k_htc` (AR9271/AR7010) + `carl9170` (AR9170)

New `rtl8814au-morrownr` completes the set of morrownr USB-WiFi forks that
mainline does **not** cover (RTL8814AU powers high-power 4-antenna adapters such
as the Alfa AWUS1900). All of morrownr's other forks (8821cu, 8822bu, 8852au/bu,
8188eu/fu, 8192eu, 8710bu) are now redundant with the in-kernel drivers above.

### Boot-timing deviation from stock (`/etc/network/interfaces`)

Mainline `rtw88`/`rtw89` USB drivers register the `nl80211` interface
**asynchronously** after USB enumeration, so on a cold boot `ifupdown` can reach
the `wlan0` stanza before the netdev exists and `wpa_supplicant` fails "interface
not found." Each `wlan` stanza gains one `pre-up` line that waits (≤20 s, polling
`iw dev $IFACE info`) for the interface to appear before launching
`wpa_supplicant`. It runs **after** the `wpa_supplicant.conf` existence guard, so
a system with no WiFi configured aborts the stanza first and never waits.

This **intentionally breaks the byte-identical parity** `docs/wifi-parity.md` §1
recorded for this file. It is the one deliberate divergence, justified by the
async-init behaviour of the mainline drivers we adopted here.

## Also in v9 (not WiFi)

Four mainline gamepad HID drivers filled the only remaining gaps in the HID set:
`HID_BETOP_FF`, `HID_BIGBEN_FF` (Nacon), `HID_MEGAWORLD_FF`, `HID_STEELSERIES`.

## Hardware verification (2026-07-13)

v9 flashed and booted on the user's DE10-Nano (verify-before-switch). Running
`linux_v9`, 6.18.33; all eight new drivers autoload-ready (`modinfo` resolves
each); RTL8822BU via `rtw88_8822bu` **auto-connected to a WPA3 5 GHz network at
boot** and passed traffic; no panic/oops/firmware-failure in dmesg;
`scripts/ci-tests.sh` 40/40. SD path checked while there: 50 MHz High-Speed mode
(hardware ceiling on this 3.3 V slot), ~22.6/10.2 MB/s read/write — no regression.

## Consequences

- **Fewer out-of-tree drivers to maintain** (6 → 3), all three remaining being the
  actively-maintained morrownr forks for chips mainline still omits.
  *(v10: now 6 → 0 — see the Update note at the top; mainline covers all three.
  v10.2: now 1, and it is not one of the original six — `rtl8852cu-morrownr`
  for a Wi-Fi 6E chip mainline drives only over PCIe.)*
- **WPA3 works** on the mainline-driven chips (mac80211 path).
- **Broader dongle support** than stock (rtw89/mt76/ath USB families added).
- **Rollback** is one defconfig line per chip (the disabled packages remain in
  the tree). Full image rollback remains the `u-boot.txt` `_vN` switch.
