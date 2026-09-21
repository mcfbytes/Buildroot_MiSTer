# BitTorrent on the MiSTer — `transmission-daemon`

The image ships upstream Buildroot's `transmission` 4.1.3 (`BR2_PACKAGE_TRANSMISSION` +
`BR2_PACKAGE_TRANSMISSION_DAEMON`, selected from `package/mister-userspace/Config.in`;
rationale in `docs/buildroot-config.md` §5.10). It is here because a growing amount of
freely redistributable material — homebrew and public-domain collections, permissively
licensed game and A/V sets, software-preservation archives — is published over BitTorrent
and nowhere else, because the publishers cannot carry the bandwidth for direct downloads.
Before this the image could fetch over HTTP, FTP, SMB, NFS and rsync and over none of the
peer-to-peer protocols, so that material needed a PC in the middle.

**This restores a stock capability, and it is not the stock package.** Stock MiSTer ships
`usr/bin/rtorrent` and `libtorrent.so.21` — in the 2025-04-02 inventory and still in the
2026-09-07 one — and this image dropped both early on, recorded in
`docs/package-manifest.md` §5 as "nothing in MiSTer's ecosystem uses a BitTorrent client
on-device". That was the use-case judgement issue #186 overturned. What the drop got right
was the ABI half, and it still holds: rakshasa's libtorrent SONAME had already drifted past
stock's `.so.21`, so there was never a clean 1:1 carry-forward to preserve. Nothing here
provides `libtorrent.so.21` — transmission links its own static `libtransmission` and shares
no code with rakshasa's library — so this is the capability back, not the ABI back.

A MiSTer is a good peer for it: often powered continuously, already carrying a large exFAT
volume, and able to keep seeding back what it fetched. The second reason is LAN-local — a
household or club with several boards should pull a set over the WAN once and have the rest
get it from each other at LAN speed, which is Local Peer Discovery, and LPD is what
eliminated every alternative (issue #186 has the survey; the short version is that
rtorrent — stock's own client, and the obvious un-drop — has a full DHT and **no LPD at
all**, and `aria2` is not in Buildroot).

> **The daemon does not run on a fresh image.** The binaries ship; nothing starts and
> nothing listens until you create one directory on the card. §2 is the whole opt-in.

---

## 1. What ships

| Binary | From | What it is for |
|---|---|---|
| `/usr/bin/transmission-daemon` | `BR2_PACKAGE_TRANSMISSION_DAEMON` | the client itself; everything else talks to it over RPC |
| `/usr/bin/transmission-remote` | the base package | the CLI you actually use — add, list, select files, start, stop |
| `/usr/bin/transmission-create` | the base package | make a `.torrent` from a directory |
| `/usr/bin/transmission-edit` | the base package | rewrite the tracker list in a `.torrent` |
| `/usr/bin/transmission-show` | the base package | dump a `.torrent`'s metadata without loading it |
| `/usr/share/transmission/public_html` | the base package | the bundled web UI, a 252 KiB prebuilt tree in the release tarball |

`transmission-remote` comes with the *base* package, not with the daemon symbol: Buildroot
never passes `-DENABLE_UTILS` and upstream defaults it `ON` (`CMakeLists.txt:64`), and
`utils/CMakeLists.txt:1` builds `create`, `edit`, **`remote`** and `show` from that one
option. Only the daemon needs its own symbol.

**`transmission-cli` is deliberately not built.** `libtransmission` is a static library, so
every binary embeds its own full copy of the engine, and `transmission-cli` has no
file-selection options whatsoever (`cli/cli.cc`) — it downloads the whole torrent, which is
the exact opposite of what §5 exists for. We would pay for a second copy of the engine to
get a tool nobody should use. `transmission-gtk` and `transmission-qt` are likewise off;
there is no X server here.

### Dependencies this pulled into the image

Seven new packages, plus one transitive: `dht`, `libb64`, `libdeflate`, `libminiupnpc`,
`libnatpmp`, `libpsl` (→ `libidn2`), `libutp`. Everything else transmission wants was
already in the rootfs — openssl, libcurl, libevent, zlib, and `libunistring` (already there
via gnutls). The bundled web UI is prebuilt in the release tarball, so no host
node/esbuild dependency appears. Installed sizes are in §9.

---

## 2. Turning it on

```sh
mkdir -p /media/fat/linux/transmission
/etc/init.d/S92transmission start
```

That is the whole opt-in. `board/mister/de10nano/rootfs-overlay/etc/init.d/S92transmission`
begins with

```sh
[ -d "$HOME_DIR" ] || exit 0
```

so on an image where nobody has created that directory the script is a no-op at every boot,
and the only trace of the feature is five binaries nobody ran. This is the same shape
`S91smb` uses for Samba (`[ -f /media/fat/linux/samba.sh ] || exit 0`) and the pattern
[ADR 0031](decisions/0031-secure-by-default-network-posture.md) names as the project's way
of shipping closed and letting the operator open it with a file on the card.

To turn it off again: stop the daemon and remove (or rename) the directory.

```sh
/etc/init.d/S92transmission stop
mv /media/fat/linux/transmission /media/fat/linux/transmission.off
```

The state is all in that directory, so renaming it is a complete, reversible uninstall —
nothing on the read-only root remembers it was ever on.

### The init script this replaces

`package/transmission` ships its own `S92transmission`, and it is wrong for this image in
two ways that both cost data rather than convenience:

- it runs the daemon as the `transmission` user. The card is mounted `fmask=0022,dmask=0022`
  with no `uid=`/`gid=`, so every file on `/media/fat` is root's and that user cannot write
  a byte of it. Ours runs as root, for the same reason `proftpd` and `smbd` do here. The
  user itself still gets created — `TRANSMISSION_USERS` in `transmission.mk` adds a
  `transmission` line to `/etc/passwd`, `/etc/group` and an empty `/var/lib/transmission`
  home inside the read-only root. Nothing on this image uses any of it; it is left alone
  rather than patched out, because suppressing it means carrying a patch against an
  upstream package for three unused lines.
- it puts `TRANSMISSION_HOME` at `/var/config/transmission-daemon`, i.e. **inside
  `linux.img`**. The root filesystem is read-only and is replaced wholesale by every OS
  update, so `settings.json`, `resume/` and `torrents/` would be destroyed on each update:
  every in-progress download restarts from zero and every seeding torrent is forgotten.

The overlay file has the same name, and Buildroot copies overlays in `target-finalize`
*after* every package has installed (`work/buildroot/Makefile:756`, `:816`), so ours is the
one that lands. Same idiom as `S49ntp` and `S91smb`, both of which overlay a
package-installed script for a similar reason (`docs/init-parity.md`).

---

## 3. The FAT-backed layout

Everything the daemon owns lives under one directory on the exFAT partition, which no OS
update touches:

```
/media/fat/linux/transmission/
├── settings.json        seeded on first start (§4), yours to edit afterwards
├── downloads/           default download-dir; move it wherever you like
├── resume/              per-torrent progress — losing this costs a full re-verify
├── torrents/            the .torrent files the daemon was given
├── blocklists/          empty unless you enable one
├── dht.dat              the DHT routing table, so a restart does not start cold
└── stats.json
```

`/media/fat/linux` is deliberate rather than arbitrary. It is where this image already keeps
the per-device state that must survive a reflash — `ssh.ext4`, `bluetooth`, `wpa_supplicant.conf`,
`samba.sh`, `user-startup.sh` — so a reader who knows the card already knows what this
directory is for. It is also the OS's own directory rather than a games directory, which
keeps a `downloads/` full of half-finished files out of the way of the per-core browsers
people actually use.

Two consequences of exFAT worth knowing before you point `download-dir` somewhere else:

- **It is mounted `sync,dirsync`.** Every write reaches the card before `write()` returns.
  That is the whole card's mount, not something this daemon chose, and it is why
  `"preallocation": 0` matters (§6).
- **There are no ownerships or modes.** `settings.json` is world-readable no matter what
  umask the daemon uses. Do not put an RPC password in it (§8).

---

## 4. `settings.json` — what the init script seeds, and why

On the first start where no `settings.json` exists, the script writes one. It never writes
over a file that is already there: this is a seed, not a policy re-applied at every boot,
so anything you edit afterwards stands — including the daemon's own rewrite of the file
when it shuts down.

```json
{
    "dht-enabled": true,
    "download-dir": "/media/fat/linux/transmission/downloads",
    "lpd-enabled": true,
    "peer-limit-global": 120,
    "peer-limit-per-torrent": 30,
    "peer-port": 51413,
    "pex-enabled": true,
    "port-forwarding-enabled": false,
    "preallocation": 0,
    "rpc-authentication-required": false,
    "rpc-bind-address": "127.0.0.1",
    "rpc-enabled": true,
    "rpc-port": 9091,
    "rpc-whitelist": "127.0.0.1,::1",
    "rpc-whitelist-enabled": true,
    "utp-enabled": true
}
```

Most of that is transmission's own default written down so it is visible. **Four lines are
not**, and they are the reason the file is seeded at all:

| Key | Upstream | Here | Why |
|---|---|---|---|
| `rpc-bind-address` | `0.0.0.0` (`libtransmission/rpc-server.h:67`) | `127.0.0.1` | Upstream binds **every interface** and relies on `rpc-whitelist` to reject non-loopback clients at the HTTP layer. That is a real open socket on the LAN, rejecting rather than absent. Binding loopback means there is nothing to reject. |
| `port-forwarding-enabled` | `true` (`session.h:429`) | `false` | Upstream asks the router for a WAN port mapping over UPnP/NAT-PMP on first run. A console should not open a hole in someone's router because it was switched on. |
| `preallocation` | `Sparse` (`session.h:480`) | `0` (off) | exFAT has no sparse files; see §6 for the measurement. |
| `peer-limit-global` / `-per-torrent` | 200 / 50 (`transmission.h:144`, `:146`) | 120 / 30 | The kernel is booted `mem=511M` (§7) — 488 MiB for all of Linux. 200 global peers is a desktop's budget, not this board's. |

`rpc-enabled` stays `true` because RPC is the only control path — `transmission-remote`
speaks nothing else — but it is now a loopback-only path. §8 is the security disposition.

Everything else in transmission's settings vocabulary that is *not* in the seed keeps its
upstream default, which for the four capabilities that motivated the package is exactly what
we want (`libtransmission/session.h:424-447`):

```
bool dht_enabled = true;    bool lpd_enabled = true;
bool pex_enabled = true;    bool utp_enabled = true;
```

Changing anything requires a restart (`/etc/init.d/S92transmission restart`) unless you set
it through `transmission-remote`, which applies immediately and is written back to
`settings.json` at shutdown.

**Logging** goes to syslog, because the daemon is not in the foreground
(`daemon/daemon.cc:322`). This image runs BusyBox `syslogd` (`S01syslogd`) with `/var/log`
symlinked to `/tmp`, so the messages land in `/tmp/messages` on tmpfs and cost the card
nothing.

---

## 5. The headless recipe

Everything below is `transmission-remote`, which talks to `127.0.0.1:9091`. It needs no
arguments to find the daemon: loopback and port 9091 are its defaults too.

### Add a torrent, paused, and look at it before it downloads anything

```sh
transmission-remote --start-paused -a '<magnet-or-url-or-file>'
transmission-remote -l                      # list torrents, with their ids
transmission-remote -t 1 -i                 # everything about torrent 1
transmission-remote -t 1 --files            # the file list
```

`--start-paused` is the important habit on a collection torrent: added running, the daemon
starts fetching **all** of it, and on a set with hundreds of gigabytes in it that is a
mistake you notice later.

### Select only the files you want

```sh
transmission-remote -t 1 -G all             # deselect everything
transmission-remote -t 1 -g 1,5,9-12        # select these
transmission-remote -t 1 -s                 # start
```

`-G` (get-none / deselect) then `-g` (get / select) is the order that matters: `-g` on its
own adds to whatever was already selected, which after an add is everything.

**Selection granularity is the piece, not the file.** Measured, on a real 978-file /
2 MiB-piece torrent: asking for one 4.63 kB file fetched 2.10 MB, and wrote *two* files —
the one asked for and the neighbour that shared its piece. `transmission-remote -t N -i`
tells you this up front, as `Total size: 5.21 GB (2.10 MB wanted)`, so check that line
before starting rather than the file's own size.

**Indices are 0-based and in the torrent's own file order** (`utils/remote.cc`), which is the
same numbering `--files` prints and the same numbering publishers cite. Ranges (`9-12`) and
comma lists work, and `all` is accepted where a list is (`utils/remote.cc:740` — an empty
index vector, which the daemon reads as "every file"). `none` is parsed as the index `-1`,
i.e. a deliberate no-op, so `-g none` does *not* deselect anything — `-G all` is the
deselect.

### Watch it, and stop it

```sh
transmission-remote -t 1 -i | grep -E 'Percent|State|ETA'
transmission-remote -t 1 -S                 # stop this torrent
transmission-remote -t 1 -r                 # remove, keep the data
transmission-remote -t 1 --remove-and-delete
transmission-remote --exit                  # shut the daemon down
```

`--exit` is a clean shutdown and flushes `resume/`; so is
`/etc/init.d/S92transmission stop`, which waits for it (§10).

### Make a torrent of your own

```sh
transmission-create -o /media/fat/linux/transmission/mine.torrent \
    -t udp://tracker.example/announce /media/fat/some-directory
```

---

## 6. exFAT and preallocation

Transmission's `preallocation` defaults to `Sparse` (`libtransmission/session.h:480`;
`0` is None, `1` Sparse, `2` Full — `open-files.h:27`). **The seed turns it off**, and the
reasoning is worth having in full, because "exFAT has no sparse files" understates it
twice over.

**Sparse is one syscall with no second chance.**
`libtransmission/open-files.cc:42` asks for `TR_SYS_FILE_PREALLOC_SPARSE`, and
`file-posix.cc:852-880` then tries exactly one thing — `fallocate64()`. The other three
implementations (XFS ioctl, Apple, `posix_fallocate`) are behind
`if ((flags & TR_SYS_FILE_PREALLOC_SPARSE) == 0)`. When `fallocate` fails,
`open-files.cc:47-60` falls back to **"the old-style seek-and-write"**: one zero byte
written at `length - 1`, then `ftruncate()`.

**On the 6.18 kernel there is no `fallocate` to succeed.** `fs/exfat` in the shipped
`linux-6.18.52` tree contains no `->fallocate` method at all — the string does not appear
anywhere in the directory — so the syscall returns `EOPNOTSUPP` and the fallback runs. That
write lands in `exfat_file_write_iter()`, which for `pos > valid_size` calls
`exfat_extend_valid_size()`: a page-by-page zeroing loop from the old valid size up to the
write offset. On a card mounted `sync`, that is the **entire file written out as zeroes**
before the first piece arrives. Sparse mode is, on this filesystem, worse than Full.

**On the RT 7.2 kernel `fallocate` works — and it still is not free.** exFAT gained the
method somewhere between the two, so on the RT channel Sparse is a real allocation. It is
synchronous (≈8.5 s per 256 MiB, measured) and it takes the space immediately: exFAT has no
per-extent "not present" state, so a preallocated 4 GiB torrent is 4 GiB off the card before
a byte of it is downloaded.

So the two kernels this image ships behave differently here, and neither behaves the way
the setting's name suggests. `"preallocation": 0` is correct on both, and it is the only
setting that spends nothing on the files selective download means you will never fetch.
§11 has the measurements.

**One consequence survives turning it off**, and is worth knowing before you blame the
daemon: `valid_size` zeroing is a property of *any* write past it, not of preallocation. A
piece landing at a high offset in a large file still makes exFAT zero everything before it.
The cost is bounded and paid once — `valid_size` only moves forward — so a torrent that
arrives roughly in order pays almost nothing, and one that arrives out of order pays it
spread across the download instead of all at once up front.

---

## 7. Scale — how big a torrent this board can hold

A single collection torrent in this space routinely reaches several thousand files, and
piece hashes alone are 20 bytes per piece for a v1 torrent. The constraint is not the card,
it is RAM, and this board has less of it than its spec sheet suggests:

```
$ cat /proc/cmdline
... mem=511M memmap=513M$511M ...
$ head -1 /proc/meminfo
MemTotal:         499708 kB
```

The DE10-Nano has 1 GiB of DDR3, and the kernel is booted with **`mem=511M`** so the upper
half stays reserved for the FPGA to DMA into. Linux gets 488 MiB, full stop, and
Main_MiSTer, the framebuffer and the page cache come out of that same 488 MiB. Treat a
torrent client here as having a couple of hundred megabytes to play with, not a gigabyte.

**Measured** (§11 has the transcript): the daemon idles at about **12 MiB** RSS, and an
11,000-file / 200,000-piece torrent — the shape a multi-terabyte collection has, whose
`.torrent` is 4.6 MB of which 4 MB is piece hashes — adds **≈ 6.2 MiB**. That is a steady
state, not a parse-time spike: it is the same after a daemon restart, when the metadata
comes back from `resume/`. Three such torrents at once left 351 MiB of the 488 MiB still
available. Roughly, budget **30 bytes per piece and a little over 100 bytes per file**.

**Recommended ceiling: keep the loaded set under about 500,000 pieces and 30,000 files** —
three torrents of the largest shape tested, ≈15 MiB of metadata. Nothing failed at or near
that; the margin is there so the daemon never competes with Main_MiSTer for the last
100 MiB. Note that torrents cost this **whether running or paused** — they are loaded at
start-up — so the way to stay under it is to remove finished collections, not pause them.

---

## 8. Security posture

The short version: **on a fresh image nothing here listens at all**, and after you opt in,
the RPC port is loopback-only and no router hole is opened.

- `rpc-bind-address: 127.0.0.1`. Control the daemon over SSH (`ssh root@mister
  transmission-remote ...`) or forward the port for the web UI
  (`ssh -L 9091:127.0.0.1:9091 root@mister`, then open `http://127.0.0.1:9091/`).
- `rpc-authentication-required: false` is safe *only* because of the line above, and the two
  must move together. If you ever set `rpc-bind-address` to `0.0.0.0` to reach the web UI
  from another machine, you must also set `rpc-authentication-required`, `rpc-username` and
  `rpc-password` — and note that `settings.json` is on exFAT, which is world-readable with no
  modes, so that password is not a secret from anything running on the box.
- `port-forwarding-enabled: false`. Transmission will still connect out, and DHT, LPD and PEX
  all work; what you lose without a forwarded port is incoming connections from peers that
  cannot initiate, which costs seeding throughput and nothing else. Turn it on deliberately
  or forward 51413/tcp+udp on the router by hand.
- **The peer port is a real listening socket** once the daemon runs — `51413` on tcp and udp,
  on every interface. That is not avoidable for a BitTorrent client; it is what opting in
  buys. There is no firewall to put in front of it: this image ships legacy `iptables` but
  the RT kernel has no `filter` table and neither kernel has `nf_tables` (ADR 0031).

The full disposition, and how it fits the rest of the image's posture, is the
**2026-09-21 amendment** to
[ADR 0031](decisions/0031-secure-by-default-network-posture.md).

---

## 9. Size

**11.91 MiB** installed (12,493,614 bytes), which took `linux.img` from 175 MiB free
(34.3%) to 163 MiB free (32.0%) against a 15% floor. Both numbers are
`scripts/check-size-budget.sh` on real builds of the two commits, same day.

**94% of that is five copies of the same engine.** `libtransmission` is a static library,
so each binary links its own:

| | bytes |
|---|---:|
| `transmission-daemon` | 2,355,228 |
| `transmission-remote` | 2,428,952 |
| `transmission-create` | 2,338,836 |
| `transmission-edit` | 2,293,780 |
| `transmission-show` | 2,310,164 |
| **the five binaries** | **11,726,960** |
| `public_html` | 238,122 |
| the eight new dependency packages, together | 524,408 |

`dht` and `libb64` contribute **zero** bytes to the target — both are static libraries that
end up inside the binaries above. The rest are ordinary shared objects: `libidn2` 193,836,
`libpsl` 103,079, `libdeflate` 98,052, `libutp` 60,040, `libminiupnpc` 50,529,
`libnatpmp` 18,872.

This table is also the `transmission-cli` argument in one line: a sixth binary would be
another ~2.3 MiB, for the one tool in the set that cannot select files.

---

## 10. Known limitations — accepted, not worked around

### No BitTorrent v2

`libtransmission/torrent-metainfo.cc:145-146` reads

```cpp
// v2, ignore for today
tr_logAddInfo("'file tree' is ignored");
```

Hybrid torrents still load and work through their v1 half. A **v2-only** torrent will not
load. If v2-only sets become common the answer is a libtorrent-rasterbar 2.x-based client
and **not** a patched transmission: the two projects share no code whatsoever —
transmission's entire external library surface is fast_float, fmt, rapidjson, small, utfcpp,
wide-integer, curl, a TLS library, libdeflate, libevent, libnatpmp, miniupnpc, dht, libpsl,
libutp and libb64. Checked rather than assumed: across the C++ sources the string
"libtorrent" occurs in exactly three places, and none of them is shared code — a peer-ID
vendor table (`libtransmission/clients.cc:553`), three comments about libtorrent's
BEP-40 behaviour (`peer-mgr.cc:268/285/337`), and the `libtorrent_resume` key
libtorrent writes into `.torrent` files (`torrent-metainfo.cc:616`). Buildroot's `libtorrent-rasterbar` is pinned to the 1.2 branch, which
is itself v1-only, so that route would start with a package bump.

### Magnet `so=` (BEP 53) is ignored

The magnet parser handles `dn`, `tr`, `ws` and `xt` and nothing else
(`libtransmission/magnet-metainfo.cc:240-267`). A publisher who hands out a per-file magnet
carrying a `so=` select-only file index gets that index **silently dropped**, and the whole
collection is queued instead. There is no error; the first sign is the size.

The workaround is §5's recipe with the index read off the magnet by hand:

```sh
transmission-remote --start-paused -a '<magnet>'
transmission-remote -t <id> --files          # 0-based, torrent file order
transmission-remote -t <id> -G all -g 1,5,9-12
transmission-remote -t <id> -s
```

`so=` uses the same 0-based, torrent-order indices that `--files` prints and `-g` takes, so
the numbers transfer across directly. This is a good candidate for a small wrapper script
that parses `so=` itself; none is shipped today.

### The shutdown wait is ours, not `start-stop-daemon`'s

Upstream's init script stops the daemon with `--retry=TERM/10/KILL/5`. BusyBox's
`start-stop-daemon` **accepts and ignores** `-R`/`--retry`
(`debianutils/start_stop_daemon.c`: *"We accept and ignore -R <param> / --retry <param>"*),
so that would be a no-op here and the daemon would be left to race its own shutdown. Our
`stop()` waits for the pidfile to disappear instead — the daemon removes it itself after
flushing `resume/` (`daemon/daemon.cc:1040`) — for up to 20 seconds. Cutting that short
costs a full re-verify of every torrent on the next start, which on a card is hours.

### Two-board LPD is untested

LPD is the standard `239.192.152.143:6771` / `[ff15::efc0:988f]:6771` pair
(`libtransmission/tr-lpd.cc:67`) and is on by default, so two boards on one LAN should find
each other with no configuration. **This has not been tested with two boards**, because
there is one rig. What *was* verified is one-sided — the announce leaves the board for the
right group and port, captured with `tcpdump` (§11). The two-board test is owed.

If you are checking it yourself: a **paused** torrent announces nothing at all
(`tr-lpd.cc:545` requires `TR_STATUS_DOWNLOAD` or `TR_STATUS_SEED`), the announce timer is
one minute (`:665`) with a 240-second floor per torrent (`:680`), and the multicast TTL is
deliberately 1 (`:681`), so the announce never leaves the local subnet. A short capture
against a paused torrent will show zero packets on a completely healthy daemon.

---

## 11. What was measured on hardware

Full transcript, with the commands and their output:
[`docs/testlogs/2026-09-21-transmission-rig.md`](testlogs/2026-09-21-transmission-rig.md).
On the HIL rig (DE10-Nano, RT 7.2.6, 488 MiB, 238 G exFAT card), 2026-09-21:

| | Result |
|---|---|
| exFAT preallocation | 256 MiB: `fallocate` 8.48 s, `ftruncate` 8.41 s, Sparse's seek-and-write fallback **21.88 s**; all three take the full 256 MiB off `df`. Card write speed 9.2 MiB/s. → `"preallocation": 0` (§6) |
| RSS, 11k files / 200k pieces | 11,940 kB idle → **18,212 kB** loaded; 18,060 kB after a restart (§7) |
| Selective download | 978-file, 5.21 GB torrent; one file selected → `2.10 MB wanted`, 2.10 MB transferred, one `Get=Yes` line out of 978 |
| DHT, all trackers removed | 16 peers in ~40 s, **every one flagged `H`** = `TR_PEER_FROM_DHT`; `dht.dat` written at shutdown, which happens only at ≥40 good nodes |
| LPD | `IP 192.168.0.160.6771 > 239.192.152.143.6771: UDP, length 141` — right group, right port |
| Listening sockets | gate held with no directory; after opt-in, `127.0.0.1:9091` (**not** `0.0.0.0`), `0.0.0.0:51413` tcp+udp, `0.0.0.0:6771` udp |
| Teardown | sockets, free space and `/media/fat/linux` all back to their pre-test state |

Two LPD gotchas found the hard way and recorded there: a **paused** torrent announces
nothing (`tr-lpd.cc:545` requires `TR_STATUS_DOWNLOAD` or `SEED`), and the announce timer
is 1 minute, so a capture shorter than ~70 s can see zero packets on a perfectly healthy
daemon.

---

## 12. See also

- `docs/buildroot-config.md` §5.10 — the two `select`s and their rationale
- `docs/decisions/0031-secure-by-default-network-posture.md` — the 2026-09-21 amendment
- `docs/init-parity.md` — where `S92transmission` sits among the init scripts
- `docs/package-manifest.md` §1 (`libtorrent.so.21`) and §5 (the `rtorrent` drop row) —
  the two places the manifest records that stock had a client and this image dropped it
- issue #186 — the survey that chose transmission over rtorrent, ctorrent, libtorrent-rasterbar and aria2
