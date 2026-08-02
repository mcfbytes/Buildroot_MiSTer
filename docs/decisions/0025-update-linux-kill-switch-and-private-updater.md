# ADR 0025 — Keep our Linux image with an `update_linux` kill switch and a private-ini updater

**Status:** Accepted (2026-08-01)
**Supersedes:** the "win the multi-db race by keeping `db.json` small" approach described
in [`docs/downloader-contract.md`](../downloader-contract.md) §9 and in earlier revisions
of [`docs/user/onboarding.md`](../user/onboarding.md).
**Related:** [ADR 0018](0018-db-json-version-is-release-date-driven.md) (version scheme),
[ADR 0020](0020-sdcard-exfat-reformat-installer.md) (`sdcard.img`).

---

## Context

`Downloader_MiSTer` applies **at most one Linux image per run**. The official
`distribution_mister` database always carries a `linux` entry, and so does ours. When more
than one configured database carries one, the Downloader chooses like this:

```python
if linux_descriptions_count > 1:
    ini_positions = {}
    for position, db_id in enumerate(self._config['databases']):
        ini_positions[db_id] = position
    position_for_unlisted = len(ini_positions)
    self._linux_descriptions.sort(key=lambda desc: ini_positions.get(desc['id'], position_for_unlisted))
```
— `src/downloader/linux_updater.py`

It sorts by **position in the ini** and takes the first. Two facts make that fatal for us:

1. `config['databases']` is populated from the base ini's sections **first**, and drop-in
   files (`/media/fat/downloader_*.ini`, `/media/fat/downloader/*.ini`) are merged in
   **afterwards**. A drop-in registration is therefore always *last*.
2. Update All pins `[distribution_mister]` to the **top** of `downloader.ini` every time it
   rewrites the file (`into_ordered_ini_dict(ini, [DB_ID_DISTRIBUTION_MISTER], ...)`).

So on any card Update All has ever touched, the official image does not merely *tend* to
win — it wins **whenever that database is actually processed** — which is most real runs, since its content changes whenever any core does. (A run where nothing changed skips the database entirely and applies no Linux image at all: `can_skip_db` returns true when `file_checking` is `FASTEST`, the steady-state default, and a skipped database's `linux` entry is never looked at.) A routine `update_all.sh` would silently replace this
project's kernel and root filesystem with the stock one, with no error and no warning.

That skip is not a reprieve, and relying on it would be a mistake: it only holds until the
next time a core is published, at which point the official database changes, is processed,
and takes the Linux slot. It also cuts the other way — it is why an *uninstall* that merely
flips the setting and waits for the user's next update can silently do nothing, which is
why `uninstall.sh` performs the revert itself with `file_checking = exhaustive`.

This project previously tried to *win* that contest. That was reasonable against older
Downloader releases, which resolved it by whichever database's document finished
downloading and parsing first — hence the standing rule that `db.json` must stay a few
hundred bytes so it would beat `distribution_mister`'s multi-megabyte catalog. That was
always a race, it was never guaranteed, and against current Downloader releases it is not
merely flaky but **always lost**.

A further constraint shapes the solution: a `release_YYYYMMDD.7z` can only carry
`files/linux/**`. The Downloader extracts nothing else. So a release can **never** write
`/media/fat/Scripts/`, which means we cannot ship a corrected updater script through the
update channel by the obvious route.

---

## Decision

**Stop competing for the Linux slot. Close it, and update out of band.**

1. **Kill switch.** `[MiSTer] update_linux = false` in `/media/fat/downloader.ini`.
   `config['update_linux']` has exactly one read site in the entire Downloader
   (`full_run_service.py`), so `false` means no database's `linux` entry is even looked at:
   no download, no rsync into `/media/fat/linux/`, no `updateboot`. Cores, ROMs, MRAs and
   every other database are completely unaffected.

2. **Private-ini updater.** `Scripts/update_linux_modernization.sh` runs the Downloader
   against its **own** ini, generated under
   `Scripts/.config/mister_linux_modernization/`, declaring exactly one database with
   `update_linux = true`, plus `--run-only` as a fail-closed assertion. One candidate means
   there is nothing to sort and nothing to lose — on every Downloader build, old or new.
   The private ini is generated in **`/tmp`**, per run, and never persists. It can live
   there because nothing about the Downloader's state derives from where the ini sits: the
   log and `.last_successful_run` are built from `base_system_path` plus the ini's
   *filename stem*, not its directory. The directory matters for exactly one thing —
   drop-in discovery globs it — and `/tmp` has no `downloader_*.ini` in it. It must **not**
   be `/media/fat` for that same reason: an ini there would drag every `downloader_*.ini`
   on the card into what is meant to be a Linux-only run.

3. **Nothing else.** No boot script, no daemon, no state file, no marker, no rootfs
   component. The two files above are the entire mechanism, and only `downloader.ini`
   persists between runs.

### Why there is deliberately no boot-time component

An earlier revision of this decision added an `/etc/init.d` script that re-applied the kill
switch each boot, canonical copies of the updater in the rootfs for it to deploy, a
`user-startup.sh` revert detector, and four state files. All of it is gone, for two
reasons.

**The running system already is the state.** `/MiSTer.version` and `uname -r` say which
image is running; `update_linux` in `downloader.ini` says whether the protection is on.
A recorded `state` file, a `REVERTED` marker and a detector to write them existed to
answer questions the system can simply be asked. `--status` asks.

**Nothing re-applies the setting, so nothing needs to be fought.** The updater is the only
thing that ever writes `update_linux`, and it only runs when the user runs it. Once the
boot script is gone, reverting is genuinely one edit and one normal update — no marker to
clear, because there is nothing to opt out of. The `no_linux_modernization` file existed
solely to stop our own boot script undoing the user's rollback.

What this gives up is real and worth stating: a corrected updater can no longer reach an
existing card automatically through an image update. Recovering that was the strongest
argument for the rootfs copies, since a `release_YYYYMMDD.7z` can only carry
`files/linux/**` and can never write `Scripts/`. The judgement is that re-running
`install.sh` — one command, already the documented way in — is a proportionate price for
deleting ~184 lines of shell and every piece of persistent state.

---

## Alternatives rejected

**Register our database via a drop-in and rely on ordering.** Cannot work: drop-ins are
merged after base-ini sections, so ours is always last, and Update All pins
`distribution_mister` first regardless. It would buy no protection at all while putting our
database into every routine core update. The shipped drop-in was removed for exactly this
reason.

**Keep racing — hold `db.json` under a kilobyte.** This is what we did. It is not a
mechanism, it is a coincidence that used to hold; current Downloader releases decide by ini
position, where we always lose. Retained only as history in `downloader-contract.md` §9.

**Give the private run its own local store.** Unnecessary and worse. The store path is a
single fixed global (`Scripts/.config/downloader/downloader.json.zip`) regardless of which
ini was used; it is loaded whole and saved whole, and databases absent from a run are
carried as non-current with their path claims still vetoing deletion. A separate store
would desynchronise from every normal run for no benefit.

**Patch or fork `Downloader_MiSTer`.** Out of scope, and against this project's whole
posture: we consume the stock update machinery unmodified so the mechanism keeps working
when upstream changes.

**Set `update_linux = false` and stop there.** Protects the image but leaves no way to
update it — the user would be frozen on whatever release they first installed.

---

## Consequences

- **A routine `update_all.sh` never changes the Linux image, in either direction.**
  Updating ours becomes a deliberate, separate action.
- **Rollback now takes two steps, not one.** Removing our database is no longer sufficient,
  because with the kill switch on, *nothing* can install a Linux image. `update_linux` must
  go back to `true` as well — which is what `--restore-stock` does, and why
  [`docs/user/rollback.md`](../user/rollback.md) was rewritten.
- **We ship a `downloader.ini`.** Update All only seeds its default databases when that file
  does not exist, so shipping one suppresses the seeding; ours therefore reproduces the
  default set explicitly (and adds `jtcores`, which a stock card does not enable).
  Deleting `[distribution_mister]` from it does **not** fall back to the built-in default —
  the Downloader only auto-adds that database when the base ini declares *none*.
- **`db.json` no longer has to stay small to be correct.** It still is, and keeping it that
  way is still preferable, but the mechanism no longer rests on it.
- **The kill switch is a global, not a per-database setting.** Any *other* third-party
  database offering a `linux` entry is also blocked while it is set. That is intended, and
  it is the same protection working as designed.
- **The kill switch protects `downloader.ini`, and only `downloader.ini`.** This is the one
  real hole, and it is worth stating precisely. The Downloader resolves its ini from the
  launcher's own filename: `calculate_config_path()` strips a `scripts` path component,
  appends `.ini` to the stem, then special-cases `/update.ini` → `/downloader.ini`. So:

  | Launcher | Ini it reads | Covered? |
  |---|---|---|
  | `Scripts/update.sh` | `/media/fat/downloader.ini` (via the special case) | ✅ |
  | `Scripts/update_all.sh` | `/media/fat/downloader.ini` — Update All always sets `DOWNLOADER_INI_PATH` explicitly, which outranks the derived path | ✅ |
  | `Scripts/update_linux_modernization.sh` | our private ini — set explicitly | ✅ (by design) |
  | **any other launcher**, e.g. a renamed copy at `Scripts/mycopy.sh` | `/media/fat/mycopy.ini` | ❌ |

  A launcher we have never heard of reads an ini we have never written. If that ini has no
  `[MiSTer]` section, `update_linux` defaults to **true**; if it declares no databases,
  `distribution_mister` is auto-added. Such a run *would* install the official image over
  ours. We do not try to defend against this by writing kill switches into arbitrary
  `/media/fat/*.ini` files — that is guessing at other tools' configuration, and would
  break them.

  It is instead handled after the fact, and cheaply: `--status` compares the running
  `/MiSTer.version` against the published one and says plainly which image you are on. If
  something did revert you, running the updater puts it back. This is deliberately *pull*
  rather than *push* — an earlier revision detected reverts from a boot script and
  announced them on the console, which cost a script, a state file and two markers to
  deliver a message most users would never see, on a screen they are not looking at.
- **Verified on hardware (2026-08-01):** on a DE10-Nano freshly flashed from `sdcard.img`,
  a full `update_all.sh` run installed 379 cores (78 of them Jotego, plus 858 MRAs),
  rebooted, and came back with `linux.img` and `zImage_dtb` byte-identical and the same
  kernel running. The Downloader's own config dump for that run recorded
  `"update_linux": false` with `"UPDATE_LINUX": "undefined"` — Update All never overrode it.
