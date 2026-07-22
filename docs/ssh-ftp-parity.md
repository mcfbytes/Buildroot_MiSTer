# SSH & FTP parity (P3.7)

> ⚠ **Both packages have moved since this analysis (noted 2026-07-22).** It was
> written against **OpenSSH 10.2p1** and **ProFTPD 1.3.8d** (Buildroot 2026.02.3).
> The build now ships **OpenSSH 10.3p1** and **ProFTPD 1.3.9a**, carried in by the
> Buildroot 2026.05.1 bump in PR #54, which did not re-run this audit.
>
> **ProFTPD is the one to look at.** OpenSSH `10.2p1 → 10.3p1` is a patch release and
> the risk analysis below is framed around behaviour changes at 8.8 / 9.0 / 9.8 —
> boundaries a patch bump cannot cross. **ProFTPD `1.3.8d → 1.3.9a` is a minor
> release**, and this document's claims about its defaults and its shipped
> `proftpd.conf` were read against 1.3.8d. That has not been re-verified.
>
> **Owner: P3.7.** Re-read the ProFTPD 1.3.9 release notes against §'s config claims,
> and confirm the shipped default config still matches what stock's `S50proftpd`
> expects. Nothing in CI asserts package versions, so this drift is caught by
> reading, not by a test.

> Scope: `BR2_PACKAGE_OPENSSH` (10.2p1) + `BR2_PACKAGE_PROFTPD` (1.3.8d) against
> stock's `sshd`/`proftpd`, using `work/imgroot` (stock's `linux.img`, extracted via
> `debugfs rdump` per `docs/reference-materials.md`) as ground truth throughout —
> not just the `docs/stock-inventory/` summaries, which for `/etc/pam.d/` in
> particular only recorded aggregate directory size, not per-file names. Where
> noted, a pre-existing `output/target/` build tree (built from this same
> defconfig by prior work, found already present in the shared repo checkout)
> was also used to empirically cross-check claims about this project's *own*
> build behavior, as distinct from stock's.

## 1. SSH

### 1.1 Host-key persistence wiring (ADR 0015) — verified intact, not touched

Confirmed present and consistent, no changes made:

- `board/mister/de10nano/rootfs-overlay/etc/init.d/S50sshd` creates/mounts
  `/media/fat/linux/ssh.ext4` at `/etc/ssh_keys`, generates `rsa`/`ecdsa`/`ed25519`
  keys on first boot only, falls back to a tmpfs keydir (with a loud `WARNING`)
  if the ext4 mount fails, and always passes `-o HostKey=...` explicitly so the
  fallback path is actually honoured.
- `board/mister/de10nano/rootfs-overlay/etc/ssh/sshd_config`'s three `HostKey`
  lines point at `/etc/ssh_keys/ssh_host_{rsa,ecdsa,ed25519}_key`, matching.
- The mount point `board/mister/de10nano/rootfs-overlay/etc/ssh_keys/` and the
  FAT-partition mount point `board/mister/de10nano/rootfs-overlay/media/fat/`
  both exist in the overlay (as empty, `.gitkeep`-tracked directories) so the
  mounts in `S50sshd` have somewhere to land.
- No `ssh_host_*` private keys anywhere in the overlay or defconfig (confirmed
  by inspection; `scripts/check-linux-img.sh` asserts this against the built
  image itself, which is the authoritative check — not re-verified here since
  that requires a build).

**Minor doc inconsistency noticed, not fixed (out of my lane — `docs/decisions/`
isn't part of this task):** ADR 0015's prose refers to "an `S49sshd`-style
overlay" in two places, but the actual (and correct, and consistent with
stock's own `S50sshd` numbering — see `docs/stock-inventory/etc-configs.md`
line 10) filename has always been `S50sshd`. Cosmetic only; behavior is
unaffected. Flagging for whoever next touches ADR 0015.

### 1.2 `sshd_config` audit for OpenSSH 10.x parity

Compared line-by-line against stock's captured config
(`docs/stock-inventory/etc-configs.md` §`/ssh/sshd_config`, `$OpenBSD:
sshd_config,v 1.103` — roughly OpenSSH 7.x-era) and against our build's actual
version (`$OpenBSD: sshd_config,v 1.105` header, OpenSSH 10.2p1 per
`OPENSSH_VERSION_MAJOR` in `work/buildroot/package/openssh/openssh.mk`).

| Directive | Stock | Ours | Verdict |
|---|---|---|---|
| `PermitRootLogin` | `yes` (uncommented) | `yes` (uncommented, comment added explaining why) | **kept, parity preserved** |
| `UsePAM` | `yes` | `yes` | **kept, parity preserved** |
| `AuthorizedKeysFile` | `.ssh/authorized_keys` | same | identical |
| `PermitUserEnvironment` | `yes` | `yes` (comment added: MiSTer scripts rely on it) | identical |
| `Subsystem sftp` | `/usr/libexec/sftp-server` | same | identical |
| `HostKey` lines | commented defaults (`/etc/ssh/ssh_host_{rsa,dsa,ecdsa,ed25519}_key`) | uncommented, repointed at `/etc/ssh_keys/...`, **no DSA entry** | intentional divergence — ADR 0015, not new |
| `ChallengeResponseAuthentication` | present (commented, old OpenSSH 7.x directive name) | absent; `KbdInteractiveAuthentication` (commented) used instead | **not a gap** — `ChallengeResponseAuthentication` is a deprecated *alias* for `KbdInteractiveAuthentication` since OpenSSH 8.7, still accepted, not removed; both are commented (no override) in both configs, so there is no behavioral difference either way |
| `UsePrivilegeSeparation` | present (commented) | absent | **not a gap** — the directive itself was made a compiled-in no-op in OpenSSH ≥7.5 and is fully **removed** in modern sshd (an *uncommented* `UsePrivilegeSeparation` line would be a fatal config-parse error on 10.x); stock's copy was already commented out (inert), so dropping the dead line entirely is strictly safer and changes nothing at runtime |

**Bottom line: no directive stock relied on was silently changed, and nothing
in stock's config would hit a removed/renamed keyword if pasted as-is into
10.2p1** (everything stock left *uncommented* — `PermitRootLogin`,
`AuthorizedKeysFile`, `UsePAM`, `PermitUserEnvironment`, `Subsystem sftp` — is
still a fully supported keyword in OpenSSH 10.x). This sshd_config was already
adapted correctly in prior work (P2.3); this audit found no further changes
needed.

**Compatibility note (not a config gap, informational only, worth an FAQ
line):** OpenSSH 10.x disables the legacy `ssh-rsa` (SHA-1) *signature*
algorithm by default (RSA host/user *keys* still work fine via
`rsa-sha2-256`/`512`), and has dropped several very old KEX/cipher names
outright. Neither stock's config nor ours pins an explicit `Ciphers`/
`KexAlgorithms`/`HostKeyAlgorithms` list (both leave these fully at the
compiled-in default), so this is an unavoidable consequence of the OpenSSH
version bump, not something a config edit can restore — a sufficiently old SSH
client (year-2016-ish) may need `-oHostKeyAlgorithms=+ssh-rsa` or similar to
connect. Worth a line in the user-facing FAQ (P4.8), alongside the ADR 0015
host-key-mismatch note.

## 2. FTP — the actual gap, and what turned out *not* to be one

### 2.1 Missing init script — confirmed and fixed

**Confirmed:** before this change, `board/mister/de10nano/rootfs-overlay/etc/init.d/`
had no `proftpd` entry at all — `proftpd` would never start.

**Fix:** added `board/mister/de10nano/rootfs-overlay/etc/init.d/S50proftpd`,
matching stock's own init-script name and number exactly (stock's real script,
`work/imgroot/etc/init.d/S50proftpd`, confirmed via
`docs/stock-inventory/etc-configs.md`: `S01syslogd S02klogd S10udev S30dbus
S40network S41dhcpcd S45bluetooth S49ntp S50proftpd S50sshd S91smb S99user`).
Content is **byte-identical** to stock (`diff` exit 0 against
`work/imgroot/etc/init.d/S50proftpd`), which is in turn byte-identical to
Buildroot's own upstream template at `package/proftpd/S50proftpd` — i.e. stock
never modified it either (verified: `diff` exit 0 across all three of
`work/imgroot/etc/init.d/S50proftpd`, `work/buildroot/package/proftpd/S50proftpd`,
and the new overlay file). Unlike `S50sshd`, this script needed **no**
ADR-0015-style rewrite: see §2.2 for why.

**Why this file is technically redundant, and why it was added anyway:**
Buildroot's `package/pkg-generic.mk` automatically installs `<PKG>
_INSTALL_INIT_SYSV` for every package whenever `BR2_INIT_SYSV` **or**
`BR2_INIT_BUSYBOX` is selected (`$(if $(BR2_INIT_SYSV)$(BR2_INIT_BUSYBOX),
$($(PKG)_INSTALL_INIT_SYSV))`, `pkg-generic.mk:367-368`). Our defconfig sets
no `BR2_INIT_*` symbol at all, so the Kconfig default (`BR2_INIT_BUSYBOX`)
applies, and `PROFTPD_INSTALL_INIT_SYSV` (`package/proftpd/proftpd.mk:160-162`)
would fire on its own, installing this exact file even without any overlay
entry. The overlay copy was added anyway, following this repo's existing
pattern of keeping every daemon's actual boot script explicit in-tree even
when a package would supply *a* default on its own: `S91smb` is an overlay
file because it's a genuine functional customization over
`package/samba4/S91smb` (extra `mkdir`s for tmpfs dirs, a `samba.sh` hook —
confirmed by `diff`, not identical); `S49ntp` is an overlay file because its
package template (`package/ntp/S49ntp.in`) is a `.in` needing build-time
`@NTPD_EXTRA_ARGS@` substitution, so the overlay pins the resolved,
reviewable text. `S50proftpd` fits neither reason — it's genuinely
byte-identical to the package default — but the same underlying motivation
applies: a single, explicit, auditable source of truth in **this** repo for
what starts each read-only-root-facing daemon, immune to a future Buildroot
version bump silently changing the upstream template's behavior.
Rootfs-overlay application happens after all package installs
(`TARGET_FINALIZE`), so this file wins either way — adding it is a no-risk,
zero-behavior-change action, not a guess about whether the automatic path
fires.

### 2.2 Read-only-root handling — confirmed working via the *existing* mechanism, no new persistence needed

Stock's `S50proftpd` needs two writable paths at boot, before `/etc/profile`'s
login-time `mount -o remount,rw /` ever runs:

- `/var/run/proftpd` (scoreboard/pidfile dir — created with plain `mkdir` if
  missing)
- `/var/log/wtmp` (created with plain `touch` if missing)

Verified via `work/imgroot/var/` (stock's own real symlink layout, byte-for-byte
matching `work/buildroot/package/skeleton-init-sysv/skeleton/var/`, Buildroot's
generic sysv skeleton — **not** something MiSTer stock customized):

```
var/run -> ../run      (tmpfs, mounted by /etc/fstab: "tmpfs /run tmpfs mode=0755,nosuid,nodev")
var/log -> ../tmp      (tmpfs, mounted by /etc/fstab: "tmpfs /tmp tmpfs mode=1777")
```

Our overlay's `/etc/fstab` is byte-identical to stock's (`diff` exit 0 against
`work/imgroot/etc/fstab`), and `/etc/inittab`'s `::sysinit:/bin/mount -a` runs
*before* `::sysinit:/etc/init.d/rcS` (which is what actually invokes
`S50proftpd`), so both tmpfs mounts are live by the time the script's `mkdir`/
`touch` run. **No ext4-image persistence trick (à la ADR 0015 / Bluetooth) is
needed or appropriate here** — the scoreboard and `wtmp` are legitimately
ephemeral, exactly as they are on stock (stock doesn't persist them across
reboots either), so reproducing stock's plain `mkdir`/`touch` is the *correct*
parity behavior, not a corner cut.

One adjacent gotcha already discovered and fixed by prior work, noted here for
completeness since it's the same failure class: `/etc/inittab` pre-creates
`/run/lock` and `/run/lock/subsys` (comment there explains `/var/lock/sshd`'s
`touch` would otherwise fail, since nothing else creates `/run/lock` itself).
`S50proftpd` doesn't hit this — `mkdir /var/run/proftpd` only needs `/var/run`
(→ `/run`, the tmpfs mount point itself) to exist, which it always does.

### 2.3 `proftpd.conf` audit

**Byte-identical to stock** (`diff` exit 0 against `work/imgroot/etc/proftpd.conf`
and against the doc-captured copy in `docs/stock-inventory/etc-configs.md`).
No changes made. Notable existing content, confirmed intentional/stock-matching:

- `<Global> RootLogin on RequireValidShell off </Global>` — root FTP login is
  allowed, same as stock.
- `DefaultRoot /` — no chroot jail; a logged-in user (including root) sees the
  whole filesystem, same as stock.
- `<Anonymous ~ftp>` block present — anonymous FTP is enabled, same as stock
  (gated in practice by whether the `ftp` system account/home exists and is
  reachable; unchanged from stock either way).
- No PAM-related directives (`AuthPAMConfig`, `AuthPAM off`, etc.) — see §3.2.

Module set also matches stock: our defconfig sets only
`BR2_PACKAGE_PROFTPD=y`, no `BR2_PACKAGE_PROFTPD_MOD_*` suboption (confirmed:
`grep PROFTPD configs/mister_de10nano_defconfig` → exactly one line). Stock's
own `usr/sbin/proftpd` dependency list (`docs/stock-inventory/binaries-needed-full.txt`:
`libc.so.6,libcrypt.so.1,libdl.so.2,libpam.so.0` — no libssl, no sqlite, no
pcre2) is consistent with the same bare/no-submodule build.

## 3. Default-credential auth posture

### 3.1 Root password — already correctly handled; initial "fix" here was wrong and has been reverted

**Corrected after a false start, recorded here so it isn't retried.**
`configs/mister_de10nano_defconfig` has `BR2_TARGET_GENERIC_ROOT_PASSWD=""`.
Read in isolation, and per Buildroot's own `system/Config.in` ("If set to
empty (the default), then no root password will be set, and root will need
no password to log in"), this looks exactly like the bug it would be if
nothing else touched `/etc/shadow` — an empty shadow field, not stock's real
`$5$...` hash (verified: `work/imgroot/etc/shadow` root field is a genuine
58-char SHA-256 crypt hash). Acting on that reading alone, this audit first
*set* `BR2_TARGET_GENERIC_ROOT_PASSWD` to a freshly generated `$5$...` hash
directly in the defconfig.

**That edit was wrong, and has been reverted (defconfig is back to
`BR2_TARGET_GENERIC_ROOT_PASSWD=""`, its original value).** The empty value
is not an oversight — `board/mister/de10nano/post-build.sh` (already present
in this worktree, not part of this task's changes) exists specifically to
pin root's password hash *after* rootfs assembly, and its own header comment
explains exactly why `BR2_TARGET_GENERIC_ROOT_PASSWD` must stay empty:

> BR2_TARGET_GENERIC_ROOT_PASSWD cannot carry a pre-hashed value reliably:
> the `$` in a "$5$salt$hash" string is eaten by make variable expansion
> before skeleton-init-common.mk's pre-encrypted detection (`$1$`/`$5$`/`$6$`)
> runs, so it silently falls through and re-hashes the mangled string with a
> RANDOM salt -- both wrong (unknown password) and non-reproducible.

In other words, the edit this audit almost shipped would have reintroduced
exactly the failure mode `post-build.sh` was written to avoid: Make eats the
`$`-delimited fields of a `$5$salt$hash` string during variable expansion
*before* `skeleton-init-common.mk` ever sees it, so the pre-encrypted-hash
detection never fires, and the mangled remainder gets treated as a
*plaintext* password and re-hashed with a **fresh random salt on every
build** — wrong password, and a P2.5/A9 reproducible-build violation to
boot. `post-build.sh` instead leaves `BR2_TARGET_GENERIC_ROOT_PASSWD` empty
and `awk`-patches `/etc/shadow`'s root field directly, post-assembly, with a
hardcoded, fixed-salt hash (`$5$MiSTer618$...`) — its own comment confirms
this is SHA-256 crypt of stock's actual, well-known default password ("1"),
i.e. **already exact stock parity**, already reproducible, already correct.

**Empirically confirmed**, not just by re-reading the script: a pre-existing
build output tree at `output/target/` (built from this same defconfig,
predating this task's changes) has `root:$5$MiSTer618$yiHxlAfaTCausfxfpep3MtaVqiqNTwl/tYeg3FF8rb1`
in its `/etc/shadow` — exactly `post-build.sh`'s hash, confirming the
mechanism already works as designed. **No defconfig change was needed or is
being made for root password parity.** `git diff` for this task's final
commit touches only the `S50proftpd` overlay file and this doc — the
defconfig is unchanged from its pre-task state.

The initial misdiagnosis happened because this audit checked
`skeleton-init-common.mk`'s handling of an empty value, confirmed it matched
the "looks like a bug" theory, and edited before checking whether
`BR2_ROOTFS_POST_BUILD_SCRIPT` (defconfig line 65, `post-build.sh`) was doing
something else with the same field — it was. Left in as a record of the
wrong turn, since the same incomplete-investigation mistake is easy to repeat
on this specific field.

### 3.2 PAM service file for FTP — audited, matches stock (nothing added)

Stock's `usr/sbin/proftpd` links `libpam.so.0` (confirmed,
`docs/stock-inventory/binaries-needed-full.txt`), and our build will too (PAM
auto-detected at `./configure` time whenever `BR2_PACKAGE_LINUX_PAM=y` is in
the staging dir, which it is — no explicit `--enable-auth-pam`/`--disable-auth-pam`
flag exists in `proftpd.mk` either way, so this isn't a config knob either
build controls). ProFTPD's compiled-in `mod_auth_pam` therefore is present in
both.

**Checked stock's actual `/etc/pam.d/` directly** (`work/imgroot/etc/pam.d/`,
not just the aggregate-size doc entry): stock ships exactly **4** files —
`login`, `other`, `sshd`, `sudo`. **No `ftp` and no `proftpd` file.** (Initial
hypothesis, before checking ground truth, was that the 4th file must be an FTP
PAM service — wrong; it's `sudo`. Recorded here so the next person doesn't
retrace the same wrong guess.)

Our build's `/etc/pam.d/` gets exactly 3 files automatically (`login` +
`other` from `linux-pam`'s own install hook; `sshd` from openssh's
`OPENSSH_INSTALL_PAM_CONF` hook, gated on `BR2_PACKAGE_LINUX_PAM=y`) —
`proftpd.mk` has **no equivalent hook**, confirmed by reading the entire file
(no `pam.d` reference anywhere in `package/proftpd/proftpd.mk`). **This
matches stock exactly** — stock's proftpd doesn't get one either. Correct
parity action: add nothing. (Deliberately not adding a `pam.d/ftp` file that
stock never had — that would be a new, undocumented divergence, and might
even change behavior in a direction nobody has audited.)

**Residual uncertainty, flagged rather than resolved:** it isn't fully
traceable statically whether Linux-PAM's "no per-service file → fall back to
`other`" behavior (which would mean `other`'s blanket `pam_deny.so` denies
*all* PAM-mediated FTP auth, root included) actually applies here, or whether
ProFTPD's `AuthOrder` chain (`mod_auth_pam` then `mod_auth_unix` by default)
treats a PAM configuration failure as "declined, try the next module" and
falls through to a plain `/etc/passwd`+`/etc/shadow` check via
`mod_auth_unix` — which is the only theory consistent with stock's own
well-established behavior (root FTP login with the default password is
known to work on real stock hardware, and stock has no `pam.d/ftp` either).
Since our proftpd build is otherwise byte-identical to stock in every
checkable dimension (`S50proftpd`, `proftpd.conf`, module set, PAM linkage),
the expectation is that it behaves identically — this is a **build-verify
item** (§4), not something resolvable by further static reading.

## 4. Verify-in-build checklist (for the orchestrator)

Both daemons require an actual boot to confirm; nothing below can be checked
from source alone.

1. **`S50proftpd` actually lands and runs**: after boot, `ls /etc/init.d/S50proftpd`
   and `pidof proftpd` (or `ps | grep proftpd`) both succeed.
2. **`S50sshd` still starts** (regression check — unrelated to this change,
   but adjacent): `pidof sshd` succeeds; `dmesg` shows no `WARNING: could not
   mount ... SSH host keys` (the ADR 0015 ext4-mount-failed fallback path).
3. **Root password works as `post-build.sh` intends** (pre-existing
   mechanism, not a change from this task, but worth confirming end-to-end
   since §3.1 nearly shipped a regression against it): `ssh root@<mister-ip>`
   and FTP login as `root`, both using stock's known default password, both
   succeed.
4. **Root SSH login is not passwordless**: confirm `ssh root@<ip>` with an
   *empty* password is refused (`PermitEmptyPasswords no`, `sshd_config`),
   i.e. that `post-build.sh`'s hash actually landed and isn't somehow still
   an empty field.
5. **`/var/run/proftpd` and `/var/log/wtmp` exist and are writable post-boot**,
   confirming the `/var/run -> /run`, `/var/log -> /tmp` symlink chain is
   intact in the actual built image (`ls -la /var/run/proftpd`; `ls -la
   /var/log/wtmp`), and that this was checked via `dmesg`/direct inspection at
   an appropriate boot stage, not via a post-login `mount` (A15 observation
   trap, `docs/decisions/0011-resolv-conf-buildroot-default.md`).
6. **`dumpe2fs`/`debugfs` check** (`scripts/check-linux-img.sh`) still
   passes — the defconfig is unchanged by this task (§3.1), so this is a
   plain regression check against the new `S50proftpd` overlay file, not a
   response to any defconfig edit.
7. **§3.2's residual uncertainty**: confirm FTP root login (item 3 above)
   specifically to settle whether PAM or `mod_auth_unix` is what's actually
   authenticating — no separate test needed beyond item 3, but worth noting
   *why* it passed if it does (check `proftpd` logs / `-d` verbose output if
   convenient, not required).

## 5. Uncertainties

- **§1.2 compatibility note**: cannot verify runtime SSH client compatibility
  claims (legacy `ssh-rsa` signature default, dropped KEX names) without an
  actual connection attempt from an old client; stated from OpenSSH's
  published release-note behavior, not observed here.
- **§2.1's "no overlay entry needed" mechanism**: originally only confirmed by
  reading Buildroot's build-system source (`pkg-generic.mk`) — since resolved
  more strongly than expected: the same pre-existing `output/target/` tree
  used in §3.1 already has `etc/init.d/S50proftpd`, byte-identical to the new
  overlay file, from *before* this task added it — direct empirical proof the
  automatic-install path really does fire on this defconfig, not just a
  source-reading inference. Doesn't gate anything either way, since the
  overlay file was added regardless (§2.1's redundancy argument).
- **§3.2**: genuinely unresolved by static analysis — see the residual
  uncertainty paragraph there and checklist item 7. This is the single
  biggest open question in this audit.
- **§3.1's `post-build.sh` mechanism** was confirmed two ways (its source,
  and the hash actually present in a pre-existing `output/target/etc/shadow`
  build) but the *end-to-end login* — does typing stock's actual default
  password at an SSH/FTP/console prompt against this specific hash really
  succeed — has not been observed in this session (no interactive login
  performed). Checklist item 3 is the outstanding confirmation.
