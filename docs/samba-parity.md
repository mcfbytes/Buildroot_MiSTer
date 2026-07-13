# Samba parity — stock (~4.14) vs. this build (4.23.8)

Task: **P3.6**. Depends on P2.1 (`BR2_PACKAGE_SAMBA4=y`) and P2.3 (init/config
parity — `docs/init-parity.md` already marked `/etc/samba/smb.conf` and
`etc/init.d/S91smb` **byte-identical to stock**). Consumed by P3.13
(hardware LAN browse test).

**Bottom line: `overlay/etc/samba/smb.conf` and `etc/init.d/S91smb` are left
byte-identical to stock, unchanged by this task.** The version-behavior audit
below (§1) found no smb.conf directive whose *default* changed between
stock's Samba (~4.14, Buildroot 2021.02.4) and this build's Samba 4.23.8 that
stock's own config exposed — every hardening change relevant to this config's
directive set landed **before** 4.14, not between 4.14 and 4.23. The one real
gap found is not in `smb.conf` at all: a read-only-root state directory
(`/var/cache/samba`) that stock's fstab never provisioned and that this
build's package install doesn't pre-bake either — fixed in `etc/fstab`
(§3). Discoverability (§2) is a documented decision, not a code change.

## Method

- Stock ground truth: `docs/stock-inventory/etc-configs.md` (P0.3, extracted
  from `release_20250402.7z`'s `linux.img`, Buildroot 2021.02.4 / Samba
  ~4.14 per `docs/version-delta.md` line 39).
- Our config: `board/mister/de10nano/rootfs-overlay/etc/samba/smb.conf` and
  `.../etc/init.d/S91smb`, confirmed byte-identical to stock's versions
  (`diff` exit 0 against `docs/stock-inventory/etc-configs.md`'s embedded
  copies, both re-verified for this task).
- Our Samba version: `SAMBA4_VERSION = 4.23.8` in
  `work/buildroot/package/samba4/samba4.mk`, built with
  `--enable-fhs --localstatedir=/var` and no AD DC / ADS / smbtorture
  (`configs/mister_de10nano_defconfig`'s existing `BR2_PACKAGE_SAMBA4=y`
  block, unchanged by this task).
- Built-image ground truth: `work/p3-rootfs/` (an extracted rootfs from a
  prior build of this repo's *current* overlay+defconfig — verified
  identical `smb.conf`/`S91smb` content before trusting it, see below) and
  `work/imgroot/` (stock's own extracted `linux.img`, P0.3). Used to check
  what's actually a symlink vs. a real directory vs. a tmpfs mountpoint,
  which files/dirs the `samba4` package pre-bakes, and that `smbd`/`nmbd`
  are both present ARM binaries. **This is inspection of pre-existing build
  artifacts, not a build run by this task** (P3.6 is author-only; no `make`
  was executed). `work/p3-rootfs/etc/samba/smb.conf` and
  `work/p3-rootfs/etc/init.d/S91smb` were diffed against this task's overlay
  copies before use and are byte-identical (`diff` exit 0 both), so they are
  a trustworthy reflection of what today's committed config actually
  produces once built — not a stand-in for a fresh verification build,
  which the orchestrator still owns.
- Samba behavior-default research: Samba release notes and `smb.conf(5)`
  via web search/fetch (sources listed at the end of each finding below).
  Where a default's exact introducing version couldn't be pinned to a single
  authoritative source, that uncertainty is stated rather than guessed.

## 1. Version-behavior audit — smb.conf directive by directive

Stock's **active** (non-`;`-commented) directives are the entire surface
area that matters — the file's ~150 commented example lines
(`[homes]`, `[netlogon]`, `guest account`, `wins support`, etc.) are inert on
both stock and here and were left untouched (still commented) for the same
reason `S50proftpd`'s hardened-vs-stock defaults were left alone in P2.3:
changing something nobody has enabled isn't parity work, it's opinion.

| Directive (stock, active) | Stock default (~4.14) | 4.23.8 default | Changed 4.14→4.23? | Verdict |
|---|---|---|---|---|
| `workgroup = MiSTer` | n/a (explicit) | n/a (explicit) | — | Keep as-is |
| `server string = MiSTer Samba Server` | n/a (explicit) | n/a (explicit) | — | Keep as-is |
| `server role = standalone server` | stable since Samba 4.0 | unchanged | No | Keep as-is |
| `log file = /var/log/samba/log.%m` | stable | unchanged | No | Keep as-is |
| `max log size = 50` | stable | unchanged | No | Keep as-is |
| `dns proxy = no` | stable (nmbd option) | unchanged | No | Keep as-is |
| `path` / `public` / `writable`\|`writeable` / `printable` (9 shares) | stable since Samba ≤3.0 | unchanged; `writeable` remains a documented synonym of `writable` in the current `smb.conf(5)` | No | Keep as-is |

None of these were touched. The interesting part of this audit is the
directives stock **doesn't set**, because that's where a version-default
change could silently break something:

| Concern (raised by task brief) | Finding | Evidence |
|---|---|---|
| SMB1/NT1 disabled by default (`client min protocol`/`server min protocol`) | **True, but predates stock.** Samba defaulted `server/client min protocol = SMB2_02` (SMB1 off) starting **Samba 4.11** (2019). Stock is 4.14 — already past that line. Not a 4.14→4.23 delta; stock's config already ran SMB1-less. | [smb.conf(5)](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html); Samba 4.11 release notes (SMB1 disabled by default) |
| `ntlm auth` default | **True it's hardened, but also predates stock.** Default changed `yes`→`no` in Samba 4.5.0, then the value was renamed `no`→`ntlmv2-only` (same behavior, new label) around Samba 4.7. Stock (4.14) already ships this default. | Samba 4.5.0 / 4.7 release notes; SambaWiki "Samba 4.7 Features added/changed" |
| `unix extensions` | Classic (SMB1-only) `unix extensions` default has been `yes` since Samba 3.0.6, and is moot once SMB1 is off (which it already was on stock). **New in 4.23**: *SMB3* UNIX Extensions (a different, SMB2/3-era feature) are enabled by default — additive, Linux/macOS-client-only, does not change Windows-visible behavior or require any `smb.conf` change. | Samba 4.23.0 release notes |
| `map to guest` / guest-access mechanics | Default is `Never` and **has been for the whole 4.14→4.23 span** — not a delta. Stock's `public = yes` shares work via true anonymous/NULL-session SMB connections (which don't go through `map to guest` at all — that parameter only governs *failed-credential* fallback), landing on the `nobody` UNIX account. Confirmed `nobody:x:65534:65534:nobody:/home:/bin/false` exists in both stock's `/etc/passwd` and this build's (`work/p3-rootfs/etc/passwd`), so the guest-account mapping target is present either way. | `smb.conf(5)` `map to guest`; `/etc/passwd` diff, both trees |
| `usershare allow guests` | Not used by stock's config (no `[global]` `usershare` block, and none of the 9 shares are usershares) — inert either version. | n/a (not present in either config) |
| Removed/renamed parameters | Checked the actual removals: **4.21** dropped `client use spnego principal`; **4.22** dropped `fruit:posix_rename` and `cldap port`. None of the three appear anywhere in stock's `smb.conf`. No fatal-parse risk from removals. | Samba 4.21.0 / 4.22.0 release notes |
| `writeable` (used by 7 of the 9 shares, vs. the `writable` spelling) | Still a live, documented synonym in the current `smb.conf(5)` — not deprecated or removed. | `smb.conf(5)`, current |

**Conclusion:** every hardening change that could plausibly have mattered
here (SMB1 off, NTLM tightened) took effect **before** stock's own Samba
version, so stock's minimal config was already written against
post-hardening defaults — there is nothing in the 4.14→4.23 jump specifically
that this config exposes. This is a narrower, better-evidenced version of
what the task brief anticipated might be a bigger gap; it turned out not to
be, and the reasoning above is the record of having actually checked rather
than assumed.

One thing this audit does **not** and cannot resolve from a worktree with no
`output/` tree: whether `testparm`/`smbd -b` actually accepts this file
cleanly end-to-end on this exact 4.23.8 build (host quirks, compiled-out
modules, etc.). Flagged for the orchestrator's build-verify pass (see §5).

## 2. Discoverability: NetBIOS (nmbd) vs. WS-Discovery (wsdd) — decision: document only, do not add

Stock's actual mechanism for "shows up under Network in Windows Explorer" is
`nmbd` (NetBIOS name service + browsing), started unconditionally alongside
`smbd` in `S91smb`. That mechanism is **structurally dead on modern
Windows**: the "Computer Browser" service that populated the Network folder
via NetBIOS browsing *required* SMB1 and was removed from Windows when SMB1
was deprecated/removed by default (Windows 10 1709+ and all of Windows 11).
`nmbd` will still start and still answer NetBIOS name queries — nothing
about Samba 4.23 removed that server-side capability — but the Windows-side
consumer of it is gone by default on any reasonably current client. The
modern replacement Windows actually uses for the Network folder is
**WS-Discovery** (UDP 3702), which Samba does not implement itself; the
common fix in NAS/embedded distros is a separate daemon (`wsdd`/`wsdd2`,
e.g. `github.com/christgau/wsdd`).

**Decision: do not add wsdd in this task.**

- **Not a Buildroot package.** `work/buildroot/package/` has no `wsdd`
  package (confirmed by listing — only `avahi` exists there, unrelated).
  Adding it would mean bringing in a new out-of-tree/custom package (same
  shape as P3.1's rtl81xx driver packages), which is a package-set decision
  outside a config-parity task's remit, and touches
  `docs/package-manifest.md` / `docs/size-budget.md` — both explicitly
  out of scope for this task.
- **The task brief itself frames this as "consider... don't necessarily
  add it."** Given the package doesn't exist upstream and would need new
  infra to add, "document the tradeoff" is the correct-sized action here,
  not a unilateral package addition.
- **Direct \\host\share access and mapped drives are unaffected either
  way** — WS-Discovery/NetBIOS browsing only affects whether the device
  *appears* in the Network folder for casual browsing; typing
  `\\MiSTer\sdcard` or mapping a drive to that UNC path works over SMB2/3
  regardless of either mechanism, and DNS/mDNS-less direct IP access also
  works unconditionally.
- **macOS** does not use either mechanism — Finder's "Network" browsing is
  Bonjour/mDNS (`avahi-daemon` on the Linux side, which `samba4.mk` will
  auto-enable via `--enable-avahi` *only if* `BR2_PACKAGE_AVAHI_DAEMON` and
  `BR2_PACKAGE_DBUS` are both set). `BR2_PACKAGE_DBUS=y` is already on;
  `BR2_PACKAGE_AVAHI_DAEMON` is not. Same reasoning applies: a new package
  addition is out of this task's scope, noted here for whoever picks up
  discoverability as its own task.

**Tradeoff, for the record:** without wsdd (or avahi for macOS), the MiSTer
will not self-announce into "Network" on a modern Windows or macOS client's
file browser — parity with stock's *mechanism* (nmbd) is preserved, but
parity with stock's *user-visible outcome* ("it just shows up") is not,
because the outcome depended on a Windows-side feature that no longer
exists by default, not on anything server-side we control. Direct-path
access (`\\MiSTer\sdcard`, mapped drives, `smb://MiSTer/sdcard` on macOS)
is unaffected and is what P3.13's real-LAN-client test should exercise
rather than relying on browse-list appearance.

## 3. Read-only-root: writable state directories smbd/nmbd need

Verified via `dmesg`, not `mount`, per the project's own established
finding (`docs/decisions/0011-resolv-conf-buildroot-default.md`): `/` is
genuinely read-only at boot; it only becomes read-write inside an
interactive **login shell**, via `/etc/profile`'s `mount -o remount,rw /`
— which has not run yet when `rcS`/`S91smb` execute during `sysinit`.
`etc/inittab`'s `::sysinit:/bin/mount -a` runs *before* `rcS`, so anything
listed in `etc/fstab` is mounted (and thus writable) by the time `S91smb`'s
`mkdir -p` calls and `smbd`/`nmbd` themselves run; anything **not** in
`fstab` and not already baked into the image as an existing directory is
not writable at that point, full stop — a bare `mkdir -p` on a missing path
under the real (ro) rootfs fails with `EROFS`, silently, because the script
has no `set -e` and none of the call sites check `$?`.

Every path `S91smb` or `smbd`/`nmbd` themselves need, checked one by one:

| Path | `S91smb` provisions it? | Backing | Verdict |
|---|---|---|---|
| `/var/log/samba` | `mkdir -p /var/log/samba` | `/var/log` is a **symlink to `../tmp`** in *both* stock (`work/imgroot/var/log -> ../tmp`) and this build (`work/p3-rootfs/var/log -> ../tmp`), and `/tmp` is tmpfs in both fstabs. So this `mkdir -p` resolves under tmpfs and succeeds. (Redundant with the script's own separate `mkdir -p /tmp/samba` line, since both ultimately land in `/tmp` — harmless, matches stock byte-for-byte, not touched.) | OK, no fix needed |
| `/tmp/samba`, `/tmp/cache`, `/tmp/cache/samba` | `mkdir -p` (all three) | `/tmp` is tmpfs (`etc/fstab`, unchanged from stock) | OK, no fix needed |
| `/var/lib/samba/private` | `mkdir -p /var/lib/samba/private` | `/var/lib/samba` is tmpfs (`etc/fstab` line 9, already present pre-P3.6, matches stock's own fstab exactly) | OK, no fix needed |
| `/var/cache/samba` (smbd's FHS `--localstatedir=/var` cache dir — `gencache.tdb` etc.) | **Not provisioned by `S91smb` at all** (stock's script never mkdir's it either) | Stock's *shipped image* has this as a real, pre-baked empty directory (`work/imgroot/var/cache/samba`, `drwxr-xr-x`, dated 2022 — baked at stock's build time, not written at runtime). **This build's package install does not pre-bake it** — confirmed empty `work/p3-rootfs/var/cache/` (no `samba` subdirectory at all). `SAMBA4_INSTALL_INIT_SYSTEMD`'s tmpfiles.d rule in `work/buildroot/package/samba4/samba4.mk` (`d /var/log/samba 755 root root`) would create the equivalent for `/var/log/samba` under `BR2_INIT_SYSTEMD`, but this image uses SysV/BusyBox init (`BR2_INIT_SYSTEMD` unset), so that hook never runs either way — moot for `/var/log/samba` (already handled by the symlink above) but confirms nothing else provisions `/var/cache/samba` for us. **This is the one genuine ro-root gap.** | **Fixed this task** — see below |
| `/run/samba` (messaging/notify sockets) | Not explicitly created by any script, on stock or here | `/run` is tmpfs (unchanged from stock); `smbd` creates its own runtime subdirectories under a writable parent at startup (standard Samba behavior — `directory_create_or_exist()` on its lock/pid/ncalrpc dirs) | OK, no fix needed — writable parent is sufficient |
| `/var/db/dhcpcd` | n/a (unrelated to Samba) | tmpfs, unchanged, listed only for completeness of the fstab diff | OK |

### The fix

`etc/fstab` gains one line (appended after the existing `/var/db/dhcpcd`
entry, same style/columns as its neighbors):

```
tmpfs		/var/cache/samba	tmpfs	mode=0755	0	0
```

`mount` (including BusyBox's) does not create missing mount points, so the
directory has to exist in the built image *before* `mount -a` runs at
`sysinit`. Added `board/mister/de10nano/rootfs-overlay/var/cache/samba/`
with a `.gitkeep` marker (git cannot track empty directories — same
convention already used by this repo for `etc/ssh_keys/.gitkeep` and
`media/fat/.gitkeep`, both from earlier P2.3/ADR-0015 work).

`0755 root root` (not `1777` like `/var/lib/samba`) because this directory
is smbd/nmbd's own internal cache, not a user-facing share or a
multi-writer directory — no reason to make it world-writable.

`S91smb` itself is **not** touched — it stays byte-identical to stock
(consistent with `docs/init-parity.md`'s existing "identical" verdict on
this file). The fstab tmpfs mount alone is sufficient, exactly the same
shape as the pre-existing `/var/lib/samba` and `/var/db/dhcpcd` entries,
which also need no corresponding `mkdir` in any init script because
`mount -a` runs before any `S`-script and the target already exists as a
directory by then.

## 4. Files changed by this task

| File | Change |
|---|---|
| `board/mister/de10nano/rootfs-overlay/etc/fstab` | +1 line: `tmpfs /var/cache/samba tmpfs mode=0755 0 0` |
| `board/mister/de10nano/rootfs-overlay/var/cache/samba/.gitkeep` | new, empty — pre-bakes the tmpfs mount point |
| `docs/samba-parity.md` | this file |

**Not changed:** `overlay/etc/samba/smb.conf`, `etc/init.d/S91smb`,
`configs/mister_de10nano_defconfig` — see §1/§3 for why each is already
correct as committed.

## 5. What this task could not verify (needs BUILD / hardware LAN, P3.13)

- **`testparm`/`smbd` actually parsing this `smb.conf` cleanly under 4.23.8,
  end to end.** §1's audit is directive-by-directory against Samba's own
  release notes and `smb.conf(5)`, plus inspection of a prior build's
  installed binaries and tree shape (`work/p3-rootfs`) — it is not a live
  `testparm -s` / `smbd -b` run against *this task's* fstab change, since
  this worktree has no `output/` tree and this task does not build.
- **`smbd`/`nmbd` actually starting** with the new `/var/cache/samba` tmpfs
  mount in place, and writing into it without error — needs the
  orchestrator's build + boot-log (`dmesg`/console) check, per this task's
  own constraint to verify ro-root claims via `dmesg`, not `mount`.
  `S91smb`'s double guard (`[ -f /media/fat/linux/samba.sh ] || exit 0`,
  restored to stock's shape in P2.3) means Samba will not even attempt to
  start on a stock/fresh image — the orchestrator's verification will need
  to drop a `samba.sh` onto the image's `/media/fat/linux/` (or equivalent)
  to actually exercise `smbd`/`nmbd` startup at all.
- **Share browsability from a real Windows and macOS client on the LAN** —
  explicitly P3.13's job, not reproducible from an author-only worktree.
  §2's discoverability conclusion (nmbd alone won't show the box in a
  modern Windows/macOS Network folder; direct `\\host\share` /
  `smb://host/share` access will still work) is inference from documented
  Windows/Samba behavior, not something this task observed on real hardware
  or a real Windows/macOS box.
