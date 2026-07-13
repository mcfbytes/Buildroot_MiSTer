# P3.13 — Full hardware matrix (run sheet)

**Status:** run sheet prepared; hardware validation since **performed (2026-07-13)**
on the integrated build (evolved through `_v9`, not the literal `_v2`→`_v3` flow
below). Confirmed working on a real DE10-Nano: **boot**, **Bluetooth** (DualSense
pairing), **WiFi** (RTL8822BU WPA3 5 GHz auto-connect at boot, via mainline rtw88
— see [ADR 0016](../decisions/0016-mainline-first-wifi-drivers.md)), and the
**Downloader** (HTTPS). **Samba and MIDI remain build/CI-verified only** (binaries
+ configs present per `ci-tests.sh`) — not yet exercised on a live device; those
rows below are still open.
**Phase 3 exit gate:** every row below is PASS or accepted-with-issue.
**Build under test:** `phase3-parity` @ latest (all of P3.1–P3.15). CI suite
`scripts/ci-tests.sh` = **40/40 PASS** on this build; that proves the software is
*present and correct in the image*, not that each device *functions* — which is
what this matrix is for.

Board is already on our stack (a Phase-2 `linux_v2.img` + `zImage_dtb_mrl`); this
flashes the complete Phase 3 build alongside it as `_v3`, so v2 stays as a
one-line rollback.

---

## Part A — Safe flash procedure (parallel files + `u-boot.txt` override)

This never overwrites the working files. Recovery from a bad boot is always
possible by restoring `u-boot.txt` (physically, or over SSH if it survives), or
holding **ESC** at power-on for the U-Boot prompt.

**Artifacts (local, this repo):** `output/images/linux.img` (512 MiB, UUID
`71916572-…`) and `output/images/zImage_dtb` (8,771,373 B). Note their sha256
before transfer; re-check on the device after.

```sh
# from the repo, over SSH (root@mister.lan, password "1")
SSH='sshpass -p 1 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@mister.lan'
SCP='sshpass -p 1 scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

# 1. Back up the current override (non-destructive)
$SSH 'cp -a /media/fat/linux/u-boot.txt /media/fat/linux/u-boot.txt.pre-p3'

# 2. Copy the new kernel + rootfs as NEW parallel names (v2 stays intact)
$SCP output/images/zImage_dtb root@mister.lan:/media/fat/linux/zImage_dtb_v3
$SCP output/images/linux.img  root@mister.lan:/media/fat/linux/linux_v3.img

# 3. Verify the copies byte-for-byte (compare against local sha256)
$SSH 'sha256sum /media/fat/linux/zImage_dtb_v3 /media/fat/linux/linux_v3.img'

# 4. Point the override at the v3 files (edit /media/fat/linux/u-boot.txt to):
#      bootimage=/linux/zImage_dtb_v3
#      mmcboot=setenv bootargs console=ttyS0,115200 $v loop.max_part=8 \
#        mem=511M memmap=513M$511M root=$mmcroot loop=linux/linux_v3.img ro rootwait; \
#        bootz $loadaddr - $fdt_addr
#    (keep the ethaddr line as-is)

# 5. Reboot and RECONNECT to prove SSH survived
$SSH reboot ; sleep 45 ; $SSH 'uname -sr; cat /MiSTer.version'
```

**Rollback:** `cp /media/fat/linux/u-boot.txt.pre-p3 /media/fat/linux/u-boot.txt`
then reboot — returns to the working v2 stack. The v3 files can be deleted later.

> ⚠ The Phase 3 image **has now been booted and validated on real hardware**
> (DE10-Nano, 2026-07-13, integrated `_v9` build: boot + Bluetooth + WiFi/WPA3 +
> Downloader confirmed). It still boots from a parallel `_vN` file with the prior
> image left intact, so recovery is a one-line `u-boot.txt` rollback: pull the SD,
> restore the previous `u-boot.txt`, reboot. Be at the device for the first flash
> of any new build.

---

## Part B — Test matrix

Fill `Result` (PASS / FAIL / N/A) and `Notes`. Rows marked **[NEW]** exercise
Phase 3 work that did not function on the P1/P2 stock-rootfs boots.

### Boot & core (regression — must still hold)

| # | Test | Expected | Result | Notes |
|---|---|---|---|---|
| 1 | Boots to MiSTer menu on HDMI | menu renders, `Version …` shown | | |
| 2 | Boot time to menu | comparable to stock (~15–25 s) | | |
| 3 | `dmesg` clean | no oops/BUG/call-trace; only known-parity warnings | | |
| 4 | Ethernet | `eth0` up, gigabit, DHCP lease | | |
| 5 | SSH + FTP | `ssh root@` works; proftpd login works **[P3.7]** | | |
| 6 | A core loads (e.g. PSX) + wired USB pad | core runs, input works (known-good baseline) | | |

### Bluetooth **[NEW — P3.3/P3.5]**

| # | Test | Expected | Result | Notes |
|---|---|---|---|---|
| 7 | BT dongle enumerates + `btusb`/`btbcm`/`btrtl` autoload | `hciconfig` shows `hci0` up | | |
| 8 | BCM20702 dongle firmware loads **[P3.14]** | `dmesg`: `BCM20702A1-0b05-17cb.hcd` loaded, no `-2` | | which dongle chip? |
| 9 | Adapter advertises as **"MiSTer"** **[P3.5]** | `bluetoothctl show` → `Name: MiSTer`, `Powered: yes` | | |
| 10 | Pair a BT controller (Just Works) | pairs + inputs in a core | | 8BitDo/DS4/etc.? |
| 11 | Pairing persists across reboot **[P3.5]** | controller reconnects after power-cycle | | |

### Wi-Fi **[NEW — P3.1/P3.3/P3.4]**

| # | Test | Expected | Result | Notes |
|---|---|---|---|---|
| 12 | Realtek dongle: driver autoloads + firmware | `wlan0` appears; which driver? | | dongle chip? |
| 13 | `wifi.sh` runs unmodified | dialog UI; scans SSIDs (`iwlist`) **[P3.4]** | | |
| 14 | Associates + gets DHCP over Wi-Fi | `wlan0` has an IP, pings out | | |

### Controllers / xone **[NEW — P3.2]**

| # | Test | Expected | Result | Notes |
|---|---|---|---|---|
| 15 | Xbox wired controller (xone) | enumerates, inputs, rumble | | |
| 16 | Xbox Wireless Dongle + controller | dongle firmware loads (`xone_dongle_02fe`/`02e6`); pairs | | which dongle PID? |

### Services & userland

| # | Test | Expected | Result | Notes |
|---|---|---|---|---|
| 17 | Samba: share browsable + read/write from a PC **[P3.6]** | `\\mister\` accessible from Win/mac | | |
| 18 | **Downloader runs** (the critical P3.9 fix) | `update.sh`/Downloader fetches over HTTPS, updates cores | | **was dead pre-P3.9** |
| 19 | `update_all` / popular community scripts | run without Python errors | | |
| 20 | MIDI / MT-32 **[P3.8]** | `aconnect -l` shows seq; MT-32 core plays (user ROMs) | | ROMs present? |
| 21 | RTC add-on (if fitted) **[P3.11]** | clock set from RTC at boot; no errors if absent | | board fitted? |
| 22 | General ALSA **[P3.15]** | `amixer`/`alsactl` present and work | | |

### Storage / regression

| # | Test | Expected | Result | Notes |
|---|---|---|---|---|
| 23 | exFAT `MiSTer_Data` / `/media/fat` | mounts, files readable, `sync,dirsync` (A13) | | |
| 24 | Save states + CHD cores | work as before | | |
| 25 | Known regression: Logitech G923 FF (task #17) | note behavior (expected loss) | | |

---

## Triage

Any FAIL → file a task, link it here, decide block-vs-accept for the exit gate.

| Row | Symptom | Task filed | Disposition |
|---|---|---|---|
| | | | |
