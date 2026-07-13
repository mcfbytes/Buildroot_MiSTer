# ADR 0016 — Mainline-first WiFi drivers (retire out-of-tree forks where 6.18 covers the chip)

**Status:** Accepted (2026-07-13) — decided by @mcfbytes, hardware-verified
**Impact:** P3.1 (WiFi kernel-module packages), P3.3 (firmware), P3.4 (WiFi
userland / `interfaces`). Changes which driver binds each USB WiFi dongle and
narrows the committed out-of-tree set. Ships in the "v9" image.
**Supersedes:** the P3.1 premise that *all six* stock out-of-tree Realtek forks
are re-sourced and built (recorded in `docs/wifi-parity.md`,
`docs/kernel-config-deltas.md`, `docs/package-manifest.md`, and
`scripts/inventory/build_modules.py`, all annotated to point here).

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
| 8812au (RTL8812AU, 11ac) | none in mainline | **kept** — `package/rtl8812au` (morrownr) |
| 8821au (RTL8811AU/8821AU, 11ac) | none in mainline | **kept** — `package/rtl8821au-morrownr` |
| 8814au (RTL8814AU, 4×4 11ac) | none in mainline | **added** — `package/rtl8814au-morrownr` (new) |

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
- **WPA3 works** on the mainline-driven chips (mac80211 path).
- **Broader dongle support** than stock (rtw89/mt76/ath USB families added).
- **Rollback** is one defconfig line per chip (the disabled packages remain in
  the tree). Full image rollback remains the `u-boot.txt` `_vN` switch.
