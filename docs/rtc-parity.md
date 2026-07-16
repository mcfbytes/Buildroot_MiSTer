# RTC parity (P3.11)

Task: **P3.11**. Depends on P1.7 (DTS — `board/mister/de10nano/linux-patches/
0004-dts-de10nano-MiSTer.patch`, `docs/dts-comparison.md` D2), P1.9 (kernel patches —
`0030-i2c-designware-quiet-timeout.patch`), P1.3 (kernel config —
`docs/kernel-config-deltas.md`), and P0.3 (`docs/stock-inventory/`). Consumed by P2.9 /
P3.13 (hardware boot verification).

## Summary

The MiSTer RTC is an **optional i2c-gpio add-on board** — a DS1307/DS3231-class chip,
bit-banged over a dedicated GPIO-based i2c bus. The DE10-Nano SoC has no built-in
battery-backed RTC. With no add-on fitted (the common case), there is no `/dev/rtc0` at
all, and that is expected, not an error.

**Stock has no init-script-based RTC handling.** System time is set from the RTC entirely
by the kernel, via `CONFIG_RTC_HCTOSYS`, before `/sbin/init` ever runs. This build
reproduces that kernel-side mechanism **exactly and only** — no userspace RTC script is
shipped, matching stock byte-for-byte on the RTC boot path.

A small defensive userspace fallback (`S05rtc`, running `hwclock -s` if `/dev/rtc0` exists)
was **considered and deliberately rejected** for strict parity — see §3. Its stated purpose
(re-asserting hctosys in case the RTC probed *after* the kernel's registration-time hook)
guards a race that **cannot occur here**: §2 proves all three candidate RTC drivers are
built into the kernel (`=y`), so they probe at kernel boot, before `RTC_HCTOSYS` runs. The
script would guard nothing stock doesn't already handle, so it is not carried.

## 1. Stock's RTC path — cited evidence

**No init script.** `docs/stock-inventory/etc-init-scripts-full.txt` is a verbatim dump of
every `/etc/init.d/S*` script on the stock image plus `inittab`/`fstab`/etc. Its full list
of `S`-scripts is:

```
S01syslogd  S02klogd  S10udev  S30dbus  S40network  S41dhcpcd
S45bluetooth (symlink -> /bin/bluetoothd)  S49ntp  S50proftpd  S50sshd  S91smb  S99user
```

(`docs/stock-inventory/etc-init-scripts-full.txt:1-616`, `docs/stock-inventory/README.md`'s
per-file index.) Grepping `hwclock|rtc|clock|adjtime|systohc|hctosys` (case-insensitive)
across `etc-init-scripts-full.txt` **and** `etc-configs.md` returns **zero matches**. There
is no `hwclock --hctosys`/`hwclock -s` call anywhere in stock's boot sequence, no `/dev/rtc*`
reference, and no `rtc-ds1307`/`rtc-pcf8563`/`rtc-m41t80` module-load line.

**Kernel-side mechanism.** `docs/stock-inventory/stock-linux.config:3045-3050`:

```
CONFIG_RTC_LIB=y
CONFIG_RTC_CLASS=y
CONFIG_RTC_HCTOSYS=y
CONFIG_RTC_HCTOSYS_DEVICE="rtc0"
CONFIG_RTC_SYSTOHC=y
CONFIG_RTC_SYSTOHC_DEVICE="rtc0"
```

`RTC_HCTOSYS` is the kernel's own "set system time from this RTC at registration" hook
(`drivers/rtc/hctosys.c`, called from `rtc_device_register()`/`__rtc_register_device()`) —
it fires the moment the RTC class device named `rtc0` is registered, which happens during
kernel boot (the i2c-gpio bus and its three candidate RTC clients are all built directly
into the kernel, not modules — see §3), well before `/sbin/init` execs, let alone any
`/etc/init.d` script runs. `RTC_SYSTOHC` is the converse (periodic system-clock → RTC
writeback). This is stock's *entire* RTC story: no init script needed or present, because
the kernel does it before userspace exists.

**Stock's RTC hardware.** `docs/stock-inventory/stock.dts:974-992` — the third and last i2c
adapter, bit-banged (`compatible = "i2c-gpio"`), with three candidate RTC chip nodes, only
one of which is populated on any given physical add-on board:

```
i2c_gpio {
    compatible = "i2c-gpio";
    gpios = <0x36 0x16 0x6  0x36 0x17 0x6>;
    rtc_at_51 { compatible = "pcf8563";  reg = <0x51>; }
    rtc_at_68 { compatible = "m41t81";   reg = <0x68>; }
    rtc_at_6F { compatible = "mcp7941x"; reg = <0x6F>; }
}
```

## 2. What this build carries — DTS + kernel config

**DTS** (`board/mister/de10nano/linux-patches/0004-dts-de10nano-MiSTer.patch`, P1.7): the
same `i2c_gpio` node and the same three candidate RTC children, ported to mainline's
vendor-prefixed compatible strings (`docs/dts-comparison.md` row D2 / §4):

```
rtc@51 { compatible = "nxp,pcf8563";       reg = <0x51>; }
rtc@68 { compatible = "st,m41t81";         reg = <0x68>; }
rtc@6f { compatible = "microchip,mcp7941x"; reg = <0x6f>; }
```

`docs/dts-comparison.md` §4 (D2) already establishes that these compatibles match 6.18's OF
match tables — re-verified directly against the pinned kernel source in this task:

| DTS compatible | Driver | OF match table hit |
|---|---|---|
| `nxp,pcf8563` | `drivers/rtc/rtc-pcf8563.c` | `pcf8563_of_match[]:569` |
| `st,m41t81` | `drivers/rtc/rtc-m41t80.c` | `m41t80_of_match[]:103` |
| `microchip,mcp7941x` | `drivers/rtc/rtc-ds1307.c` | `ds1307_of_match[]:1142` |

**Kernel config** (`board/mister/de10nano/linux.config`): the driver `=y` lines are present
verbatim, byte-identical to stock's:

```
CONFIG_RTC_CLASS=y
CONFIG_RTC_DRV_DS1307=y   # covers mcp7941x (rtc@6f)
CONFIG_RTC_DRV_PCF8563=y  # covers nxp,pcf8563 (rtc@51)
CONFIG_RTC_DRV_M41T80=y   # covers st,m41t81 (rtc@68)
```

All three are **built directly into the kernel image (`=y`), not modules** — same as stock.
This is *more* robust than the module-autoload path the task brief anticipated: there is no
`depmod`/`modalias`/hotplug dependency at all for RTC detection. The driver's `i2c_driver`
registers at kernel boot and binds the moment the i2c-gpio bus scan finds a chip acking at
0x51, 0x68, or 0x6f; if none does (no add-on fitted), no RTC class device is ever created,
`rtc0` never exists, and `RTC_HCTOSYS`/`RTC_SYSTOHC` are silent no-ops (their code paths are
gated on a `rtc0`-named class device existing at all).

**`RTC_HCTOSYS`/`RTC_HCTOSYS_DEVICE`/`RTC_SYSTOHC` are not listed verbatim in
`board/mister/de10nano/linux.config`.** This was checked, not assumed: `linux.config` is
`savedefconfig` output (`docs/kernel-config-deltas.md`), which by design omits any symbol
that already resolves to its upstream Kconfig default via `make olddefconfig`. `RTC_HCTOSYS`
and `RTC_SYSTOHC` default to `y` (and `RTC_HCTOSYS_DEVICE`/`RTC_SYSTOHC_DEVICE` default to
`"rtc0"`) once `RTC_CLASS=y` is set and `ALWAYS_USE_PERSISTENT_CLOCK` is off (true on
`socfpga`). **Verified directly, not just argued from Kconfig defaults**, against the
orchestrator's own most recent full build output (read-only; not part of this worktree, not
modified):

```
$ grep RTC_HCTOSYS\|RTC_SYSTOHC output/build/linux-6.18.33/.config
CONFIG_RTC_HCTOSYS=y
CONFIG_RTC_HCTOSYS_DEVICE="rtc0"
CONFIG_RTC_SYSTOHC=y
CONFIG_RTC_SYSTOHC_DEVICE="rtc0"
```

**No kernel/DTS gap. No change requested of P1.7/P1.3.** This is a positive finding, not a
gap: the resolved config already matches stock byte-for-byte on every RTC-relevant symbol.

## 3. A userspace `S05rtc` fallback — considered and rejected

An `S05rtc` init script (running `hwclock -f /dev/rtc0 -s` when `/dev/rtc0` exists, a no-op
otherwise) was drafted during this task and then **dropped**, for strict stock parity. The
reasoning, recorded here so the decision isn't re-litigated:

- **Stock ships no such script**, and parity is this project's default. Adding a script stock
  lacks needs a real, evidenced justification — and there isn't one.
- **The race it would guard cannot occur.** Its only substantive rationale was "re-assert
  hctosys if the RTC probes *after* `RTC_HCTOSYS`'s registration-time hook." But §2 proves
  all three candidate RTC drivers are built into the kernel (`=y`, not modules), so they
  probe at `device_initcall` time — *before* the `late_initcall`-era `RTC_HCTOSYS` hook. By
  the time any userspace init script could run, the kernel has already set the clock (or
  there is no board and there is nothing to set). The script would re-read the RTC and set
  the clock to the value the kernel already set it to — pure redundancy.
- **Small correctness risk for zero benefit.** `busybox hwclock -s` re-interprets the RTC's
  time (UTC by default); in the corner case where its assumption diverged from the kernel's,
  it could *change* a clock the kernel already set correctly. Not worth it to duplicate work
  the kernel already does.

The only thing `S05rtc` offered was a one-line boot-log confirmation, which does not justify
a parity deviation. **Result: no userspace RTC script; kernel `RTC_HCTOSYS` only, exactly
like stock.** (`hwclock` remains available for manual/debug use, but it is now the
**util-linux** `hwclock` — `BR2_PACKAGE_UTIL_LINUX_HWCLOCK=y`, with the BusyBox `CONFIG_HWCLOCK`
applet disabled — matching stock, which shipped util-linux's `hwclock` too. It is still simply
not wired into boot. See `docs/util-linux-parity.md`.)

**No Buildroot `defconfig` changes needed for this task.** The one pre-existing RTC-related
line needed no change: `configs/mister_de10nano_defconfig:366` —
`BR2_PACKAGE_I2C_TOOLS=y  # for the i2c-gpio RTC add-on, P3.11` (installs `i2cdetect`/
`i2cget`/`i2cset` for bench debugging of the bit-banged bus).

## 4. No-RTC no-op behavior

With no add-on board fitted (the common case):
- The i2c-gpio bus scan at 0x51/0x68/0x6f finds nothing; no RTC class device is created;
  `/dev/rtc0` never exists.
- `RTC_HCTOSYS`/`RTC_SYSTOHC` have nothing to act on — no kernel log noise from them either
  way (they only log on the class device they're watching, which never registers).
- The pre-existing i2c-designware "controller timed out" bus-scan message is already
  downgraded from `dev_err` to `dev_dbg` by `linux-patches/0030-i2c-designware-quiet-
  timeout.patch` (P1.9) specifically because most boards have no RTC fitted — this is
  cosmetic log-level parity, not new to this task, but directly relevant: it's *why* a
  no-add-on boot is silent rather than noisy.
- With no userspace RTC script shipped (§3), there is nothing in boot to run, log, or fail.
  **No errors, no output, no side effects** — identical to stock.

## 5. What needs HARDWARE to fully verify — [HW], P3.13

`docs/dts-comparison.md` §6 already flags this as unverifiable on the bench: *"That the RTC
add-on board is detected. Vendored compatibles match 6.18's OF tables (D2), but no one here
has the add-on board. → P3.11 (RTC parity)."* This task's contribution narrows that gap to a
concrete, minimal HW checklist for P3.13:

- [HW] With no RTC board attached: boot log shows no i2c/rtc errors
  (`dmesg | grep -i rtc` and `dmesg | grep -i 'i2c.*timed out'` at `dev_dbg`, not visible at
  default log level).
- [HW] With an RTC board attached (any of the three candidate chips — PCF8563, M41T81/
  M41T80-family, or MCP7941x): `/dev/rtc0` exists; `dmesg | grep -i rtc` shows the driver
  binding (e.g. `rtc-pcf8563 0-0051: registered as rtc0`) **and** the kernel's own
  hctosys line (`rtc-pcf8563 0-0051: setting system clock to …`); `date` after boot (with
  the board's battery holding a previously-set time and networking disabled, to isolate RTC
  from NTP) reflects the RTC's time, not the Buildroot build epoch or `1970-01-01`.
- [HW] `hwclock -w` (write system time to RTC) round-trips: set system time, write to RTC,
  power-cycle, confirm `/dev/rtc0`'s time survived and the kernel picks it back up at boot.
- [HW] Confirm which of the three candidate chips is actually populated on the physical
  MiSTer RTC add-on board sold/documented by the project, and confirm its address matches
  one of 0x51/0x68/0x6f (this doc assumes the DTS's three candidates are exhaustive, per
  stock; P3.13 should confirm against a real board).

None of the above can be exercised without a physical i2c-gpio RTC add-on board — this
worktree has no `output/` tree and does not build. The orchestrator's shared build +
in-image verification covers the no-RTC no-op path (boot with no board shows no errors);
the with-RTC path is [HW]-only, per P3.13.
