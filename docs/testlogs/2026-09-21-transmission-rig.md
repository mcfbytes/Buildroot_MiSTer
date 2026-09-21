# transmission on the HIL rig — 2026-09-21

**Date:** 2026-09-21
**Board:** Terasic DE10-Nano, the HIL rig (`192.168.0.160` / `mister.lan`), real hardware
**Image under test:** the rig's installed beta, `/MiSTer.version` = `260916`
**Kernel:** `7.2.6` `#1 SMP PREEMPT_RT` (the RT channel), `armv7l`
**RAM:** `MemTotal: 499708 kB` — the kernel is booted `mem=511M memmap=513M$511M`, so
Linux has **488 MiB** and the FPGA has the rest of the 1 GiB
**Card:** `/dev/mmcblk0p1`, 238.7 G exFAT, mounted
`rw,noatime,nodiratime,sync,dirsync,fmask=0022,dmask=0022,iocharset=utf8,errors=remount-ro`
**Binaries under test:** `transmission-daemon` / `-remote` / `-create` / `-edit` / `-show`
from this branch's own build (`output/target/usr/bin`), copied to the rig's `/tmp` and run
from there — the rig's installed image predates this change and has none of them.

Everything created for these tests was deleted afterwards; §7 is the teardown check.

> **Scope note.** The rig runs the **RT 7.2** kernel. Where a result depends on the kernel
> rather than on userspace — which, for §1, it does — the 6.18 result is derived from the
> shipped kernel's own source and is labelled as such rather than claimed as measured.

---

## 1. exFAT preallocation — the reason the seed says `"preallocation": 0`

### What transmission actually does

`libtransmission/session.h:480` defaults `preallocation_mode` to `Sparse`. Sparse is not
"skip it": `libtransmission/open-files.cc:42` calls
`tr_sys_file_preallocate(fd, length, TR_SYS_FILE_PREALLOC_SPARSE)`, which in
`file-posix.cc:852-880` tries exactly one thing — `fallocate64()` — and on failure
`open-files.cc:47-60` falls back to **"the old-style seek-and-write"**: write one zero byte
at `length - 1`, then `ftruncate()` to `length`.

So on a filesystem without `fallocate`, Sparse mode means *writing into* a
several-hundred-megabyte hole before the first piece of the torrent arrives.

### What each of the three paths costs on this card

Measured on the rig, 256 MiB each, on the real exFAT card (`sync,dirsync`), `time(1)`:

| Path | Time | `df` free delta | What it is |
|---|---:|---:|---|
| `fallocate -l 256M` | **8.48 s** | 262,144 KiB | what Sparse tries first |
| `truncate -s 256M` (pure `ftruncate`) | **8.41 s** | 262,144 KiB | what Sparse's fallback finishes with |
| seek-and-write + truncate | **21.88 s** | 262,144 KiB | Sparse's fallback, in full |
| `dd bs=1M count=256` (sequential) | **27.92 s** | 262,144 KiB | the card's own write speed, ≈9.2 MiB/s |

```
=== A. fallocate -l 256M ===
real	0m8.484s
rc=0
df free delta (KiB): 262144
=== C. truncate -s 256M (pure ftruncate) ===
real	0m8.409s
df free delta for C (KiB): 262144
=== D. seek-and-write fallback, then truncate ===
real	0m21.877s
df free delta for D (KiB): 262144
=== E. plain sequential write, for the card speed baseline ===
256+0 records out
real	0m27.920s
```

### Three findings, and the one that decides the default

**a. "Sparse" is not sparse on exFAT — every path consumes the full length immediately.**
All four rows above take the same 262,144 KiB out of `df`. exFAT has no per-extent
"not present" state, so there is nothing for a sparse file to be. Preallocating a 4 GiB
torrent takes 4 GiB off the card before a byte of it is downloaded, and gives it back only
if the torrent is removed with its data.

**b. On the 6.18 kernel, Sparse degrades to a full zero-fill.**
`fs/exfat` in the shipped `linux-6.18.52` tree contains **no `->fallocate` at all** — the
string `fallocate` does not appear anywhere in the directory, so `vfs_fallocate()` returns
`-EOPNOTSUPP` and transmission takes the seek-and-write fallback. That write lands in
`exfat_file_write_iter()`, which for `pos > valid_size` calls `exfat_extend_valid_size()`
(`fs/exfat/file.c`) — a page-by-page `write_begin` / `folio_zero_new_buffers` /
`write_end` loop that zeroes **everything from the old valid size up to the write offset**.
On a `sync` mount every one of those pages goes to the card. The 21.88 s row is that loop:
13.5 s more than the 8.4 s of pure allocation, for 256 MiB of zeroes.
*Source-derived, not measured — the rig runs RT 7.2 (see below). It is not a judgement
call: with no `->fallocate` method there is no other path the syscall can take.*

**c. On the RT 7.2 kernel, `fallocate` works — and it is still not free.**
`fallocate -l 256M` returned 0 on the rig, so exFAT gained a `->fallocate` between 6.18
and 7.2. It costs 8.48 s per 256 MiB (≈30 MiB/s of cluster allocation, metadata only, but
synchronous) and, per (a), takes the space immediately. **The two kernels this project
ships therefore behave differently here**, which by itself is a reason not to rely on
either: `"preallocation": 0` is correct on both.

`fallocate` on this image is BusyBox's applet (`/usr/bin/fallocate -> /usr/bin/busybox`),
which calls `fallocate(2)` directly and `bb_perror_msg_and_die`s on any error, so rc=0 is
the syscall's own result and not a fallback.

### The consequence that survives turning preallocation off

exFAT's `valid_size` zero-fill is a property of *any* write past it, not of preallocation.
With `"preallocation": 0`, a piece that lands at a high offset in a large file still makes
the driver zero everything before it. The cost is **bounded and paid once** — `valid_size`
only moves forward — so a torrent that arrives roughly in order pays almost nothing, and
one that arrives out of order pays up to the file's length spread over the download instead
of all at once before it starts. Off is still the better of the two: it never spends the
time on files or regions that selective download means you will never fetch.

**Verdict: the init script seeds `"preallocation": 0`.**

---

## 2. Scale — RSS with large torrent metadata loaded

### Method

Three synthetic torrents, added `--start-paused` and never verified against real data.
Synthetic because the shape is the variable: a `.torrent` is bencode, so a file with N
entries and M fabricated 20-byte piece hashes exercises exactly the parse and the
in-memory structures that a real collection torrent of that shape would, with none of the
uncertainty about what else a third party's torrent happens to contain. The biggest is
11,000 files / 200,000 pieces / 3.28 GB nominal — the shape issue #186 named — and its
`.torrent` is **4,572,135 bytes**, of which 4,000,000 is piece hashes.

### The clean number

Daemon restarted first, so this is one torrent against a fresh process:

| | `VmRSS` |
|---|---:|
| daemon running, no torrents | **11,940 kB** |
| + the 11k-file / 200k-piece torrent | **18,212 kB** |
| same, after a daemon restart (metadata reloaded from `resume/`) | **18,060 kB** |
| after removing it | 14,132 kB |

**≈ 6.2 MiB of RSS for an 11,000-file, 200,000-piece torrent**, and the restart line says
that is a steady state rather than a parse-time spike. Removing it does not give all of it
back (14.1 MiB, not 11.9) — ordinary allocator retention, not a leak that grows.

### Three at once, for the marginal cost

From the first pass, adding them one after another to the same process:

| Loaded | `VmRSS` | Δ |
|---|---:|---:|
| none | 12,232 kB | |
| + 1,000 files / 20,000 pieces | 13,164 kB | +932 kB |
| + 5,000 / 100,000 | 17,612 kB | +4,448 kB |
| + 11,000 / 200,000 | 21,720 kB | +4,108 kB |

Adds took 1 s, 3 s and 6 s of wall clock respectively. With all three resident — 17,000
files and 320,000 pieces — the board still reported **351 MiB available** of its 488 MiB.

### The recommended ceiling

RSS runs at roughly **30 bytes per piece plus a little over 100 bytes per file**, on top
of a ~12 MiB daemon. The binding constraint is not transmission, it is that Main_MiSTer,
the framebuffer and the page cache share the same 488 MiB.

**Recommendation: keep the resident set of torrents under about 500,000 pieces and 30,000
files — roughly 15 MiB of metadata RSS, three torrents of the largest shape tested.** That
is a comfortable margin, not a cliff: nothing failed at the sizes above, and the number is
chosen so that a MiSTer running a core never competes with the daemon for the last
100 MiB. Torrents you are not actively fetching or seeding cost this whether paused or
not — they are loaded at start-up — so the way to stay under it is to remove finished
collections, not to pause them.

---

## 3. Selective download

The real thing, on a real multi-hundred-file torrent: the Internet Archive item
`lecture8_2607_librivox` (a scanned 19th-century French magazine, CC **Public Domain
Mark 1.0**), **978 files, 5.21 GB, 2,482 pieces of 2 MiB**, fetched as
`lecture8_2607_librivox_archive.torrent`.

```
transmission-remote --start-paused -a lecture8.torrent
transmission-remote -t 2 -G all          # deselect all 978
transmission-remote -t 2 -g 976          # take one: the 4.63 kB meta.xml
transmission-remote -t 2 -s
```

Immediately after the two selection calls, before starting:

```
  Total size: 5.21 GB (2.10 MB wanted)
```

and when it finished:

```
  State: Idle
  Percent Done: 100%
  Have: 2.10 MB (2.10 MB verified)
  Total size: 5.21 GB (2.10 MB wanted)
  Downloaded: 2.10 MB

lecture8_2607_librivox (978 files):
  #   Done Priority Get      Size  Name
976:  100% Normal   Yes 4.63 kB    lecture8_2607_librivox/lecture8_2607_librivox_meta.xml
```

`976:` is the only line with `Get = Yes` out of 978. **2.10 MB transferred out of a
5.21 GB torrent.**

**What is actually on disk is the useful surprise**, and it is worth knowing before anyone
reports it as a bug:

```
4629      downloads/lecture8_2607_librivox/lecture8_2607_librivox_meta.xml
2092523   downloads/lecture8_2607_librivox/.____padding_file/493
```

**Selection granularity is the piece, not the file.** The wanted 4.63 kB file shares its
2 MiB piece with an archive.org pad file, so the whole piece was fetched and both files
were written. On a torrent with a large piece size, "one small file" costs one piece.
(The `.____padding_file/` tree is archive.org's own convention — `transmission-show`
prints a note saying it may be deleted once retrieval completes.)

---

## 4. DHT with every tracker removed

`debian-13.7.0-amd64-netinst.iso.torrent`, with its one tracker stripped by our own
`transmission-edit`, so the announce list really is empty:

```
$ transmission-edit -d http://bttracker.debian.org:6969/announce debian.torrent
Changed 1 files
$ transmission-show debian.torrent
TRACKERS

WEBSEEDS
```

Added and started, with a 30 kB/s global cap so this stayed a DHT test rather than a
download:

```
  t+0s    State: Idle        Peers: connected to 0, uploading to 0, downloading from 0
  t+10s   State: Idle        Peers: connected to 0, ...
  t+20s   State: Idle        Peers: connected to 0, ...
  t+30s   State: Idle        Peers: connected to 0, ...
  t+40s   State: Downloading Peers: connected to 16, uploading to 0, downloading from 6
```

```
Address                Flags   Done    Down     Up  Client
31.217.179.15          TDEH     100     0.0    0.0  qBittorrent/5.1.0
31.217.179.177         TDEH     100    16.4    0.0  qBittorrent 5.2.3
31.217.179.50          TDEH     100     8.2    0.0  qBittorrent/5.2.3
109.137.166.96         TDEH     100     0.0    0.0  qBittorrent/5.2.2
...                                                  (16 peers, 13 shown)
```

**Every peer carries `H`**, which `libtransmission/peer-mgr.cc:1908-1911` assigns for
`TR_PEER_FROM_DHT` and nothing else. With no trackers at all, the DHT found 16 peers in
about 40 seconds and the transfer started (548.6 kB before it was removed).

**Independent confirmation that the routing table reached a ready state.** `dht.dat` is
written only in `~tr_dht_impl()`, and only `if (is_ready(AF_INET) || is_ready(AF_INET6))`
(`tr-dht.cc:168`). `is_ready` is `swarm_status >= Firewalled` (`:263`), and `swarm_status`
returns `Broken` below 4 good nodes and `Poor` below **40** (`:245-252`). After a clean
`S92transmission stop`, the card had:

```
-rwxr-xr-x  1 root root  799  Sep 21 03:01  /media/fat/linux/transmission/dht.dat
```

so the session ended with at least 40 good DHT nodes. Worth recording precisely because it
is asymmetric evidence: the file's *presence* proves readiness, its *absence* does not
disprove it. A later, three-minute session did **not** rewrite it — too short to
re-establish 40 *good* nodes — which is the expected behaviour of that guard, not a
regression.

---

## 5. LPD announces

Captured on `eth0` while a real, non-private torrent was in `TR_STATUS_DOWNLOAD`:

```
# tcpdump -n -i eth0 -c 4 'udp port 6771'
02:49:11.535715 IP 192.168.0.160.6771 > 239.192.152.143.6771: UDP, length 141
```

Right group, right port — `239.192.152.143:6771`, which is what
`libtransmission/tr-lpd.cc:67` declares. The socket is also visible in §6 as
`udp 0.0.0.0:6771`.

**Two conditions had to be met to see this, and the first attempt saw nothing** — worth
recording so the next person does not conclude LPD is broken. `tr-lpd.cc:545` announces
only for torrents where `allows_lpd` (i.e. not private) **and**
`activity == TR_STATUS_DOWNLOAD || TR_STATUS_SEED`. A *paused* torrent produces no
announces at all, and the first capture was run against paused synthetic probes: 0 packets
in 25 s. The announce timer is 1 minute (`:665`) with a 240 s per-torrent floor (`:680`),
so a capture needs to be at least ~70 s long.

**Two-board discovery is NOT tested and is owed.** There is one rig. This confirms the
send side reaches the right multicast group with the right payload size; it does not
confirm that a second MiSTer receives it, joins the group and connects. `TtlSameSubnet`
is 1 (`:681`), so the announce is deliberately confined to the local subnet.

---

## 6. Listening sockets — the ADR 0031 regression oracle

**Before anything** (the rig as it normally runs), matching ADR 0031's own inventory:

```
tcp  0.0.0.0:22     sshd
tcp  0.0.0.0:21     proftpd
udp  192.168.0.160:123 / 127.0.0.1:123 / 0.0.0.0:123   ntpd
udp  0.0.0.0:68     dhcpcd
```

**With `/media/fat/linux/transmission` absent**, `S92transmission start` printed nothing,
returned 0, and left no process — the opt-in gate. Sockets unchanged.

**After `mkdir` + start**:

```
tcp  127.0.0.1:9091    <- RPC, loopback ONLY
tcp  0.0.0.0:51413     <- peer port
udp  0.0.0.0:51413     <- peer port (uTP)
udp  0.0.0.0:6771      <- LPD multicast
```

`9091` is on `127.0.0.1`, not `0.0.0.0`. That is the whole point of seeding
`rpc-bind-address`: upstream's default would have put an RPC port on every interface,
relying on the whitelist to reject rather than on not listening.

The seeded `settings.json` was read back from the card after the daemon rewrote it at
shutdown, and all five deviations had survived:

```
"peer-limit-global": 120,      "peer-limit-per-torrent": 30,
"port-forwarding-enabled": false,
"preallocation": 0,
"rpc-bind-address": "127.0.0.1",
"download-dir": "/media/fat/linux/transmission/downloads"
```

The daemon also expanded the file to its full 90-key form, which is expected and is why
the script seeds once and never rewrites: everything not in the seed is upstream's
default, now written down where the operator can see and edit it.

Directory layout after first start, all of it on the card:

```
bandwidth-groups.json  blocklists/  downloads/  resume/  settings.json  torrents/
```

plus `dht.dat`, `queue.json` and `stats.json` once the daemon has run and stopped.

---

## 7. Teardown

```
$ rm -rf /media/fat/linux/transmission /tmp/tm && sync
$ ls -d /media/fat/linux/transmission ; ls -d /tmp/tm
ls: /media/fat/linux/transmission: No such file or directory
ls: /tmp/tm: No such file or directory
$ pidof transmission-daemon
no transmission process
$ netstat -tuln
tcp  0.0.0.0:22 ; tcp  0.0.0.0:21 ; udp *:123 (x3) ; udp 0.0.0.0:68
$ df -h /media/fat | tail -1
/dev/mmcblk0p1   238.7G   92.7G   146.0G  39%  /media/fat
```

Listening sockets are back to exactly the pre-test set, free space is back to exactly the
pre-test 146.0 G, and `/media/fat/linux` contains only what it contained before. Nothing
is left running and nothing is left listening.

---

## 8. What this did NOT test

- **Two-board LPD** (§5) — one rig. Owed.
- **The 6.18 kernel's exFAT path** (§1b). The rig runs RT 7.2; the 6.18 result is derived
  from `fs/exfat` having no `->fallocate` method, which is not a judgement call but is not
  a measurement either.
- **A long-running seed.** Everything here ran for minutes. Nothing is known about the
  daemon over days, about `resume/` rewrite wear on the card, or about syslog volume on
  the `/var/log -> /tmp` tmpfs.
- **`transmission-daemon` started by `rcS` at boot.** The init script was exercised
  directly (`start`, `stop`, the gate, the seed, the shutdown wait), but the rig runs an
  image that predates this change, so the boot-time path is CI-verified only
  (`scripts/ci-tests.sh`), not observed.
- **BitTorrent v2 and magnet `so=`** — source-verified limitations (`docs/bittorrent.md`
  §10), not exercised here.
