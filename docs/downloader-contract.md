# The `LinuxUpdater` contract (`Downloader_MiSTer`)

**Task:** P0.6. **Constraint index:** A8. **Consumers:** P4.4 (release workflow), P4.5
(db.json generation/publishing), P4.8 (user docs).

**Pinned source commit:** `MiSTer-devel/Downloader_MiSTer` @
`915315668b9460b0fcdfc728be8254fe698c479f` (branch `main`, 2026-07-08). **Every citation
below is `file:line` at this exact commit.** Permalink template:

```
https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/<file>#L<line>
```

e.g. the core version-compare line is
[`src/downloader/linux_updater.py#L74`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L74).

Local copy used to derive every citation: `work/Downloader_MiSTer` (gitignored; see
`docs/reference-materials.md` §5 for clone provenance — `git -C work/Downloader_MiSTer
rev-parse HEAD` reproduces the pinned SHA above). Stock artifact facts (hashes, the
`updateboot` script, the extracted archive layout) are re-verified in this document
directly against `work/extracted/` and `work/release_20250402.7z`, not merely copied from
`docs/verification/stock-release-20250402.md` — see the "Corrections and additions"
callouts throughout for where this task's re-verification went beyond, or refined, that
earlier document.

Two files carry almost the whole contract: `src/downloader/linux_updater.py` (the state
machine) and `src/downloader/constants.py` (every path/hash/URL constant). Everything
else cited below (`db_entity.py`, `db_utils.py`, `online_importer.py`, `job_system.py`,
`config_reader.py`, `config.py`, `file_system.py`, `jobs/fetch_file_worker.py`,
`update_output.py`, `main.py`) was reached by grepping outward from those two files, per
the task brief.

---

## 1. The db.json `linux` schema

A DB's `linux` field is parsed with **almost no internal validation** — this is itself
the first load-bearing fact:

```python
self.linux: Optional[dict[str, Any]] = db_props.get('linux', None)
if self.linux is not None and not isinstance(self.linux, dict): raise DbEntityValidationException(...)
```
[`src/downloader/db_entity.py#L70-71`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/db_entity.py#L70)

`DbEntity.__init__` only checks that `linux`, if present, is *a dict*. None of its
sub-fields (`hash`, `size`, `url`, `version`) are type- or presence-checked at parse
time — they are read later, unchecked, by `LinuxUpdater`. A malformed `linux` object
(missing key, wrong type) will raise an uncaught `KeyError`/`TypeError` deep inside
`_update_linux_impl`/`SafeFileFetcher.fetch_file`. This does **not** crash the whole
process silently — `main.py` wraps the entire run in a top-level handler that prints a
traceback and returns exit code 1 (`src/downloader/main.py#L87-93`) — but it does abort
the run *after* file installation for other dbs already completed, with no linux-specific
diagnostic. **This is exactly why P4.5's task text already mandates a schema self-check
in the publish job** — the Downloader will not catch our mistakes for us.

### `linux` sub-fields, as actually consumed

| Field | Type | Required? | Consumed at | Meaning |
|---|---|---|---|---|
| `hash` | string (lowercase hex MD5) | De facto yes — used unconditionally | `src/downloader/jobs/fetch_file_worker.py#L121-123` (`SafeFileFetcher.fetch_file`, compared via `TypedDict` field `description['hash']`) | MD5 of the **entire downloaded `.7z` file**, not of any file inside it. See §2. |
| `size` | int (bytes) | De facto yes | `fetch_file_worker.py#L126-128` | Exact byte size of the `.7z` file. Mismatch after hash success still fails the fetch. |
| `url` | string | De facto yes | `fetch_file_worker.py#L118` (`self._fetcher.fetch_file(description['url'], path)`) and `linux_updater.py#L88` (`self._fetcher.fetch_file(linux, FILE_Linux_uninstalled)` — the whole `linux` dict is passed as the `SafeFetchInfo`) | Direct HTTP(S) URL to the release `.7z`. No redirects are special-cased beyond what `http_gateway` does generically. |
| `version` | string | De facto yes | `linux_updater.py#L74`: `linux['version'][-6:]` | Only the **last 6 characters** are ever read. Any longer string works (`"v0.1-250402"` would compare its trailing `"250402"`); by convention this is the bare `YYMMDD`. |

`SafeFetchInfo` (the type the `linux` dict is cast to when fetching) is:
```python
class SafeFetchInfo(TypedDict):
    url: str
    hash: str
    size: int
```
[`src/downloader/constants.py#L21-24`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/constants.py#L21) —
note `version` is *not* part of this type; it is read directly off the raw dict inside
`linux_updater.py`, not through the fetch path. **No other fields of `linux` are read
anywhere in this codebase** (grepped the full `src/downloader` tree for `linux[` and
`linux.get(`; the four above are the complete set).

### The db.json envelope `linux` lives inside

`linux` is one key of a full database document. `DbEntity.__init__` requires these
top-level keys to exist on **any** db.json, independent of whether it carries a `linux`
key at all:

```python
if 'db_id' not in db_props: raise DbEntityValidationException(...)
if 'files' not in db_props: raise DbEntityValidationException(...)
if 'folders' not in db_props: raise DbEntityValidationException(...)
if 'timestamp' not in db_props: raise DbEntityValidationException(...)
```
[`src/downloader/db_entity.py#L39-42`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/db_entity.py#L39)

Plus: `self.db_id: str = str(db_props['db_id']).lower()` and it **must equal the
lower-cased downloader.ini section name it's loaded under**, or the whole db is rejected
(`db_entity.py#L46-47`: `if self.db_id != section.lower(): raise
DbEntityValidationException(f'Section "{section}" does not match database id
"{self.db_id}". Fix your INI file.')`). `timestamp` must be an int (`db_entity.py#L48-49`).
`files`/`folders` must be dicts, but **may be empty** (`db_entity.py#L50-53`) — a db.json
whose only purpose is shipping a `linux` entry can validly have `"files": {}, "folders":
{}`. `zips`/`archives`/`base_files_url`/`tag_dictionary`/`default_options`/`v` all default
to empty/absent if omitted (`db_entity.py#L54-72`).

**Consequence for P4.5:** the smallest valid, schema-correct db.json we can publish is
`db_id` + `timestamp` + empty `files`/`folders` + `linux`. Keep it that small — §9 below
explains why this is not just tidiness but load-bearing for the multi-db race.

---

## 2. MD5 hash scope: the whole archive, verified before extraction ever runs

The hash in db.json covers **the entire `release_YYYYMMDD.7z` file as downloaded**, not
any file inside it. Verification happens in `SafeFileFetcher.fetch_file`, called from
`LinuxUpdater._update_linux_impl` at the point the archive is fetched to
`/media/fat/linux.7z`:

```python
error = self._fetcher.fetch_file(linux, FILE_Linux_uninstalled)
```
[`src/downloader/linux_updater.py#L88`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L88)
(`FILE_Linux_uninstalled = '/media/fat/linux.7z'`, `constants.py#L88`).

```python
def fetch_file(self, description: SafeFetchInfo, path: str) -> Optional[Exception]:
    i = self._retries
    while True:
        _file_size, error = self._fetcher.fetch_file(description['url'], path)
        ...
        if error is None:
            file_hash = self._file_system.hash(path)
            if file_hash != description['hash']:
                error = FileValidationError(...)
        if error is None:
            file_size = self._file_system.size(path)
            if file_size != description['size']:
                error = FileValidationError(...)
        i -= 1
        if error is None or i <= 0: break
        self._waiter.sleep(10)
    return error
```
[`src/downloader/jobs/fetch_file_worker.py#L112-136`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/jobs/fetch_file_worker.py#L112)
— retried up to `downloader_retries` (default 3, `config.py#L162`) times, 10 s apart.

`self._file_system.hash(path)` calls `hash_file()`:
```python
def hash_file(path: str) -> str:
    with open(path, "rb") as f:
        file_hash = hashlib.md5()
        chunk = f.read(COPY_BUFSIZE)
        while chunk:
            file_hash.update(chunk)
            chunk = f.read(COPY_BUFSIZE)
        return file_hash.hexdigest()
```
[`src/downloader/file_system.py#L659-666`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/file_system.py#L659)
— **MD5**, streamed over the whole file, confirming the official db entry's `hash` field
is exactly `md5sum release_YYYYMMDD.7z`. Verified independently this session:
`md5sum work/release_20250402.7z` → `8dc3acae7d758a80a363fbd7ad31d95d`, matching the
official db.json entry and `docs/reference-materials.md`'s recorded value byte-for-byte.

There is a **separate, later** integrity check with `7za t` (§4) — that one tests the
7z container's internal CRCs (catches silent corruption the MD5 wouldn't, e.g. a bit flip
introduced by something other than the original download), not a duplicate of this
whole-file hash. Both must pass before extraction proceeds.

The pinned `7za` binary itself goes through the **same** `SafeFileFetcher.fetch_file`
path, with its own hash/size, before the archive's hash is even checked in sequence terms
— see §4.

---

## 3. Version comparison: inequality against the rootfs-root `/MiSTer.version`

```python
current_linux_version = self.get_current_linux_version()
if current_linux_version == linux['version'][-6:]:
    self._logger.debug(...)
    return
```
[`src/downloader/linux_updater.py#L73-76`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L73)

```python
def get_current_linux_version(self):
    return self._file_system.read_file_contents(FILE_MiSTer_version) if self._file_system.is_file(FILE_MiSTer_version) else 'unknown'
```
[`linux_updater.py#L102-103`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L102),
with `FILE_MiSTer_version: Final[str] = '/MiSTer.version'` —
[`constants.py#L87`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/constants.py#L87).
This is the **rootfs root**, i.e. `/MiSTer.version` as seen by a process running on the
live system — **not** `/media/fat/linux/MiSTer.version` (a common misconception the
Downloader's own author evidently didn't fall into, but plenty of forum posts do; PLAN §3
already calls this out and this task confirms the exact source line it rests on).

**It is a strict string inequality, not an ordering comparison.** There is no numeric
parse, no date comparison, no `<`/`>`. Whatever string sits at `/MiSTer.version` is
compared byte-for-byte against `linux['version'][-6:]`; if they differ *at all*, the
update proceeds — including to a lexicographically "smaller" string. **This is exactly
what makes rollback work** (§8): shipping a db.json whose `version` ends in an *older*
date than the currently-running one is sufficient to trigger a "downgrade," because the
code has no concept of downgrade — only "same" or "different."

### Missing `/MiSTer.version`

If the file doesn't exist, `get_current_linux_version()` returns the literal string
`'unknown'` (`linux_updater.py#L103`, the ternary's else-branch). `'unknown'` can never
equal a `version[-6:]` slice of a real db entry, so **the update always proceeds** in this
case, every single Downloader run, until a build ships a matching `/MiSTer.version`. This
generalizes the "botched version string" hazard the task text flags: it's not just a typo
risk, it's the *default* failure mode of a completely missing file.

### The exact-byte-match hazard (a hard requirement on P2.6)

`read_file_contents` performs no stripping:
```python
def read_file_contents(self, path: str) -> str:
    full_path = self._path(path)
    with open(full_path, 'r') as f:
        return f.read()
```
[`file_system.py#L351-355`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/file_system.py#L351)
— whatever bytes are in the file are compared, whitespace and all. Verified this session:
the stock rootfs's `/MiSTer.version` (`work/imgroot/MiSTer.version`) is **exactly 6 bytes**,
`250402`, **no trailing newline** (`wc -c` → 6; `xxd` shows `3235 3034 3032` with nothing
after). If our `post-build.sh` (P2.6) ever writes this file with a trailing `\n` (an easy
`echo` vs `printf`/`echo -n` mistake), `current_linux_version` becomes `"250402\n"` (7
bytes), which will **never** equal any 6-character slice of a db `version` field — the
inequality is permanently true. Consequence: the Downloader will re-fetch and reflash the
*entire* Linux image on **every single run**, forever — re-running `updateboot` (which
wipes the U-Boot saved environment, §6) and cycling flash writes to the boot partition on
every scheduled Downloader invocation. This is the literal mechanism behind the "infinite
update loop" the task brief warns about, not a hypothetical. **P4.4/P4.5 must assert**
`wc -c` on the built image's `/MiSTer.version` equals exactly 6, with no trailing
whitespace, as a release-blocking check.

---

## 4. On-demand pinned `7za`: fetched once, then reused

Nothing in the installed image can extract a 7z archive. The Downloader fetches a static
ARM `7za` binary the first time it ever needs one, and thereafter reuses the copy already
on the SD card:

```python
if not self._file_system.is_file(FILE_7z_util):
    self._update_output.linux_update_phase('fetch_7z')
    error = self._fetcher.fetch_file(FILE_7z_util_uninstalled_description(), FILE_7z_util_uninstalled)
    if error is not None:
        self._update_output.linux_update_failed('fetch_7z', str(error)); return
```
[`linux_updater.py#L93-98`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L93)

```python
FILE_7z_util: Final[str] = '/media/fat/linux/7za'
FILE_7z_util_uninstalled: Final[str] = '/media/fat/linux/7za.gz'
def FILE_7z_util_uninstalled_description() -> SafeFetchInfo: return {
    'url': 'https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/raw/master/7za.gz',
    'hash': 'ed1ad5185fbede55cd7fd506b3c6c699',
    'size': 465600
}
```
[`constants.py#L89-95`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/constants.py#L89)

Fetch goes through the same hash+size-verified `SafeFileFetcher` path as the main archive
(§2). Once downloaded, it's decompressed in place and the `.gz` deleted:
```python
if self._file_system.is_file(FILE_7z_util_uninstalled):
    result = subprocess.run(f'gunzip "{FILE_7z_util_uninstalled}"', shell=True, stderr=subprocess.STDOUT)
    self._file_system.unlink(FILE_7z_util_uninstalled)
    if result.returncode != 0:
        self._update_output.linux_update_failed('fetch_7z', ...); return
if not self._file_system.is_file(FILE_7z_util):
    self._update_output.linux_update_failed('fetch_7z', '7z is not present in the system. Aborting Linux update.'); return
```
[`linux_updater.py#L106-116`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L106)

**`/media/fat/linux/7za` persists across updates.** Our archive's `files/linux/` payload
does *not* include a `7za`/`7za.gz` (confirmed: the stock archive's `files/linux/` listing
in `docs/reference-materials.md` has no such entry), and the later `rsync` (§6) has no
`--delete`, so an already-installed `7za` is left untouched by every subsequent update.
**One fetch, forever reused**, unless a user deletes it.

### Hard compatibility constraint on our archive (P4.4)

Whatever we ship **must be extractable by that exact, old, pinned `7za` build**
(MD5 `ed1ad5185fbede55cd7fd506b3c6c699`) — not "some 7-Zip," that specific static ARM
binary, whatever version it is. Verified this session directly against the extracted
stock archive:

```
$ 7z l -slt work/release_20250402.7z | grep -E "^(Method|Solid|Blocks)"
Method = LZMA2:26 LZMA:20 BCJ2
Solid = +
Blocks = 2
```

The stock archive is a **solid** 7z using **LZMA2** for most members, a **BCJ2** filter
(x86 branch/call/jump converter — almost certainly auto-applied by the Windows 7-Zip GUI
to the ELF binaries it packed, e.g. `files/MiSTer` and the Windows `.exe`), and a
supplementary plain **LZMA** stream (a normal BCJ2 side-effect: BCJ2 splits its input into
main/call/jump/range sub-streams, and the main stream is usually still LZMA/LZMA2-coded).

**Recommendation for P4.4:** don't reproduce BCJ2 — it's an artifact of what the Windows
GUI happened to auto-detect, not a requirement, and it adds encoder complexity for no
benefit to us (our archive doesn't need to squeeze an x86 executable). A plain solid
LZMA2 archive (`7z a -mx=9 -m0=lzma2`, no BCJ/BCJ2/ARM filter, no encryption, no split
volumes) is well within what any 7-Zip-family extractor from the last two decades
understands, including old static ARM `7za` builds — LZMA2 predates them by years. What
*is* required is testing it against the actual pinned binary, not assuming compatibility:
fetch `7za.gz` from the pinned URL above (hash-verify it against
`ed1ad5185fbede55cd7fd506b3c6c699`), `gunzip` it, and in CI run that **exact** ARM `7za`
(under `qemu-arm`, since it's an ARM static binary) against our freshly-built archive:
`7za t our_release.7z` (integrity) and `7za x -y our_release.7z files/linux/*
-o<scratch>` (the actual extraction command the Downloader runs, §5) — assert both exit 0
and that the extracted `files/linux/` tree matches what we intended to ship. This is the
literal command sequence the field code runs; testing anything less specific (e.g. a
modern `7z` on the CI runner) doesn't prove the constraint.

---

## 5. Extraction: integrity test, then `files/linux/*` only

```python
result = subprocess.run('''
        sync
        RET_CODE=
        if {0} t "{1}" ; then
            if [ -d /media/fat/linux.update ]
            then
                rm -R "/media/fat/linux.update" > /dev/null 2>&1
            fi
            mkdir "/media/fat/linux.update"
            if {0} x -y "{1}" files/linux/* -o"/media/fat/linux.update" ; then
                RET_CODE=0
            else
                rm -R "/media/fat/linux.update" > /dev/null 2>&1
                sync
                RET_CODE=101
            fi
        else
            echo "Downloaded installer 7z is broken, deleting {1}"
            RET_CODE=102
        fi
        rm "{1}" > /dev/null 2>&1
        exit $RET_CODE
'''.format(FILE_7z_util, FILE_Linux_uninstalled), shell=True, stderr=subprocess.STDOUT)
```
[`linux_updater.py#L120-142`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L120)

Two distinct 7z invocations, in order:

1. **`7za t "/media/fat/linux.7z"`** — tests the **whole archive's** internal CRCs (not
   limited to `files/linux/`). This is on top of, not a substitute for, the whole-file MD5
   already checked in §2 — it catches corruption the MD5 wouldn't (the MD5 was already
   confirmed correct before this even runs; this step exists to catch a 7z-format-level
   inconsistency, e.g. an archive that hashes correctly as a file but has an internal CRC
   mismatch from a bug in whatever produced it).
2. **`7za x -y "/media/fat/linux.7z" files/linux/* -o"/media/fat/linux.update"`** —
   extracts **only paths under `files/linux/`** (the pattern is 7z's own internal-path
   wildcard, matched against archive entries — the rest of the archive, `files/MiSTer`,
   `files/menu.rbf`, `files/Scripts/update.sh`, the Windows `.exe`, exists solely to serve
   the Windows SD-card installer GUI and is never touched here). Destination is
   `/media/fat/linux.update/`, so the extracted tree lands at
   `/media/fat/linux.update/files/linux/*` (the `files/linux/` prefix is preserved — see
   the `mv`/`rsync` source paths in §6, which reference exactly that nesting).
   *(Minor implementation note, not a behavior change: because this whole block runs
   under `shell=True` → `/bin/sh -c`, the unquoted `files/linux/*` token is technically
   subject to the shell's own pathname expansion before 7z ever sees it. In practice no
   `files/linux/` directory exists relative to the Downloader's working directory, so the
   shell leaves the glob unexpanded and passes it through literally to `7za` as intended —
   but this is incidental shell behavior (POSIX: an unmatched glob with no `nullglob`/
   `failglob` is passed through verbatim), not a guarantee.)*

Exit-code discipline here is explicit and correct: `RET_CODE` is set on every branch and
the script ends with `exit $RET_CODE`, so `result.returncode` faithfully reflects which
of "corrupt archive" (102) / "extract failed" (101) / "ok" (0) occurred, regardless of
what the trailing `rm` does. **Contrast this with the flash phase in §7 — the same file's
next subprocess block does *not* do this**, which matters for §10.

```python
if result.returncode != 0:
    self._update_output.linux_update_failed('extract', 'Error code: %d' % result.returncode)
    return
```
[`linux_updater.py#L144-146`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L144)
— on any extract failure, `/media/fat/linux.7z` has already been deleted by the script
itself (`rm "{1}"` runs unconditionally), `/media/fat/linux.update` has been cleaned up on
the failure path, and nothing under `/media/fat/linux/` or `linux.img` has been touched
yet. This is the **safest** failure point in the whole flow (see §10).

---

## 6. User-file restore: patch the **new** image, offline, before it's swapped in

If any of the six well-known files exist on the current `/media/fat/linux/`, they get
staged for restoration *before* the archive is even fetched:

```python
for source, destination in FILE_Linux_user_files:
    if self._file_system.is_file(source):
        self._user_files.append((source, destination))
```
[`linux_updater.py#L78-81`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L78)

```python
FILE_Linux_user_files: Final[list[tuple[str, str]]] = [
    ('/media/fat/linux/hostname',     '/etc/hostname'),
    ('/media/fat/linux/hosts',        '/etc/hosts'),
    ('/media/fat/linux/interfaces',   '/etc/network/interfaces'),
    ('/media/fat/linux/resolv.conf',  '/etc/resolv.conf'),
    ('/media/fat/linux/dhcpcd.conf',  '/etc/dhcpcd.conf'),
    ('/media/fat/linux/fstab',        '/etc/fstab'),
]
```
[`constants.py#L96-104`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/constants.py#L96)

After a successful extract, if any of those six source files exist, `_restore_user_files`
runs, and it operates on the **freshly extracted, not-yet-active** image:

```python
def _restore_user_files(self) -> bool:
    temp_dir = tempfile.mkdtemp()
    mount_cmd = 'mount -t ext4 /media/fat/linux.update/files/linux/linux.img {0}'.format(temp_dir)
    result = subprocess.run(mount_cmd, shell=True, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        self._update_output.linux_update_failed('user_files', 'Could not mount updated Linux image, try again later. Error code: %d' % result.returncode)
        return False
    ...
    for source, destination in self._user_files:
        image_destination = temp_dir + destination
        try:
            self._file_system.copy(source, image_destination)
        except Exception as e:
            copy_error = True
            break
    ...
    unmount_cmd = 'umount {0}'.format(temp_dir)
    result = subprocess.run(unmount_cmd, shell=True, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        self._update_output.linux_update_failed('user_files', 'Could not unmount updated temporary Linux image. Error code: %d' % result.returncode)
        return False
    if copy_error:
        self._update_output.linux_update_failed('user_files')
        return False
    return True
```
[`linux_updater.py#L175-216`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L175)

Key facts, all directly from the quoted code:

* `mount -t ext4 <img> <dir>` with **no `-o ro`/`-o loop` option** — a plain `mount -t
  ext4` of a regular file mounts it **loop, read-write** by default (the loop device setup
  is implicit; the kernel auto-loop-mounts a regular file passed to `mount`). This is the
  "mounted rw" the task brief refers to, confirmed at the exact line, not inferred.
* The mounted image is `/media/fat/linux.update/files/linux/linux.img` — the **new**,
  not-yet-installed image, still sitting inside the extraction staging directory. The
  currently-running `linux.img` is never touched by this step.
* Destinations are computed as `temp_dir + destination`, i.e. literally
  `<tmp>/etc/hostname`, `<tmp>/etc/hosts`, `<tmp>/etc/network/interfaces`, etc. — this
  requires those six paths to exist as **regular files** inside our built image (not
  symlinks into tmpfs, not missing), because `self._file_system.copy` (a plain file copy,
  no `mkdir -p`) will fail if the parent structure or target isn't there in the shape it
  expects. This is A8/A9's "must remain regular files" clause, now traced to the exact
  copy call that requires it.
* Any single copy failure `break`s the loop immediately (remaining files in the list are
  simply *not* restored — this is a partial-restore risk worth naming explicitly: if
  `hostname` copies but `hosts` fails, the mount still gets cleanly unmounted and the
  function returns `False`, but the new image now has the user's custom `hostname` and the
  **stock/our** `hosts` file, an inconsistent mix. Not fatal — the overall update aborts
  right after (`_run_subprocesses` returns without ever running the flash phase, so the
  half-patched new image never becomes the active `linux.img` at all) — but worth
  documenting so P4.8's troubleshooting section doesn't wrongly assume "user files"
  failures are all-or-nothing.
* On any failure here (mount, copy, unmount), the function returns `False` and
  `_run_subprocesses` returns immediately without reaching the flash phase
  (`linux_updater.py#L148-151`) — the currently-active `/media/fat/linux/linux.img` is
  never touched. Safe failure point, same as §5.

---

## 7. The apply flow, in exact order

Numbered steps, each with its source citation. All of §5–§7 happens inside
`_run_subprocesses` (`linux_updater.py#L105-173`).

1. **Integrity test:** `7za t /media/fat/linux.7z` (§5, `linux_updater.py#L123`).
2. **Extract `files/linux/*` only** into `/media/fat/linux.update/` (§5, `linux_updater.py#L129`).
3. **User-file restore**, only if any of the six source files exist: mount the new
   `linux.update/files/linux/linux.img` read-write at a temp dir, copy the six files in,
   unmount (§6, `linux_updater.py#L148-151` gating the call; `L175-216` the implementation).
4. **Flash phase** — one shell script, quoted in full because its ordering and its (lack
   of) error handling both matter (§10):
   ```bash
   sync
   mv -f "/media/fat/linux.update/files/linux/linux.img" "/media/fat/linux/linux.img.new"
   rsync --exclude="gamecontrollerdb/" --out-format='%n' -a "/media/fat/linux.update/files/linux/" "/media/fat/linux/"
   rm -R "/media/fat/linux.update" > /dev/null 2>&1
   sync
   /media/fat/linux/updateboot
   sync
   mv -f "/media/fat/linux/linux.img.new" "/media/fat/linux/linux.img"
   sync
   touch /tmp/downloader_needs_reboot_after_linux_update
   ```
   [`linux_updater.py#L157-168`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L157)

   In order:
   1. `mv` the (already user-file-patched, if applicable) new `linux.img` out of the
      staging area to `/media/fat/linux/linux.img.new` — same filesystem, so this is a
      rename, not a copy.
   2. `rsync -a --exclude="gamecontrollerdb/"` the **rest** of `files/linux/` (everything
      the extract staged **except** `linux.img`, which was already moved out in the
      previous step) over `/media/fat/linux/`. This is how `updateboot`, `MidiLink.INI`,
      `ppp_options`, `u-boot.txt_example`, `_samba.sh`, `_user-startup.sh`,
      `_wpa_supplicant.conf`, `mt32-rom-data/`, `soundfonts/`, `zImage_dtb`, and
      **`uboot.img`** all get replaced with whatever we ship. Confirmed: `gamecontrollerdb/`
      is excluded exactly as `docs/verification/stock-release-20250402.md` states — the
      `--exclude="gamecontrollerdb/"` flag is right there in the command, verified against
      this exact line, not just re-asserted. Since there is no `--delete`, anything present
      in the destination but absent from our shipped payload (e.g. a previously-fetched
      `7za`, or files a user dropped in manually) is left alone.
   3. Remove the now-empty staging dir; `sync`.
   4. **Run `/media/fat/linux/updateboot`** — note this executes the copy that `rsync` just
      placed there, i.e. **our** `updateboot`/`uboot.img`, not the previous ones. See §8.
   5. `sync`.
   6. `mv -f linux.img.new linux.img` — the actual swap. This is the **last** step that
      changes which root filesystem image is active, and it happens **after** `updateboot`
      has already run.
   7. `sync`; `touch /tmp/downloader_needs_reboot_after_linux_update`.
5. **Reboot flag.** Constant confirmed at
   [`constants.py#L107`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/constants.py#L107):
   `FILE_downloader_needs_reboot_after_linux_update: Final[str] = '/tmp/downloader_needs_reboot_after_linux_update'`
   — matches PLAN/the verification doc exactly. Checked by
   `LinuxUpdater.needs_reboot()` (`linux_updater.py#L218-219`), which gates a
   30-second-warning auto-reboot in `FullRunService._run`
   (`src/downloader/full_run_service.py#L95-117`, using
   `REBOOT_WAIT_TIME_AFTER_LINUX_UPDATE = 30` seconds, `constants.py#L35`, vs. the 5-second
   standard reboot wait), subject to the `allow_reboot` setting
   (`AllowReboot.ALWAYS` is the default — `config.py#L158`, `#L64-67`).

**Why order matters (the task brief's own framing, now sourced):** the six user-file
destinations are patched into the image **while it is still just a file sitting in a
staging directory** — before `rsync`, before `updateboot`, before the final `mv` makes it
`linux.img`. This is only possible because our image is a plain ext4 file mountable rw by
whatever e2fsprogs/kernel combination is running *at update time on the user's currently
booted system* (a constraint on the **currently installed** Linux doing the mounting, not
on the new image's own kernel) — and because the six paths exist as regular files at
predictable `/etc/...` locations inside it (A9/P2.5's ext4-generation-pinning and P2.3's
"regular files, not symlinks" requirement are both downstream of this exact code path).

---

## 8. `updateboot`: flashes our `uboot.img` and wipes the saved environment, every time

Full contents (407 bytes, verified `wc -c` this session), from
`work/extracted/files/linux/updateboot` (shipped **inside** the archive, in
`files/linux/`, and placed at `/media/fat/linux/updateboot` by the `rsync` in step 4.2
above — it is not part of the Downloader's own source, it's a payload file we ship and
the Downloader merely executes by path):

```sh
#!/bin/sh

if [ -f /media/fat/linux/uboot.img ]; then

	echo ""
	echo "Erasing u-boot saved environment"
	dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=1 count=1
	echo ""

	if [ -b /dev/mmcblk0p3 ]; then
		echo "Using old layout"
		dd if=/media/fat/linux/uboot.img of=/dev/mmcblk0p3
	else
		echo "Using new layout"
		dd if=/media/fat/linux/uboot.img of=/dev/mmcblk0p2
	fi
	
	echo ""
	echo "Done."
	echo ""
fi
```

Hashes (this session, `work/extracted/files/linux/updateboot`):
MD5 `6451e3f7fafeac5aff4e47013fec23a9`,
SHA-256 `6ff2d50a080e26d7173b61c52083e9cc42ca658db0c5031b4da1c45c74a562f2`.

Two hard, unconditional consequences every time this script runs (i.e. every linux
update, official or ours — it's invoked unconditionally in step 4.4 of §7 whenever
`/media/fat/linux/uboot.img` exists, which it always does on a real MiSTer SD card):

1. **`dd if=/dev/zero of=/dev/mmcblk0 bs=512 seek=1 count=1`** zeroes 512 bytes at raw
   sector 1 (byte offset 512) of the **whole disk device**, not a partition —
   unconditionally, before the boot image is even written. The script's own comment calls
   this "Erasing u-boot saved environment." **No U-Boot saved-environment state survives
   a linux update, full stop** — whatever `u-boot.txt` sets on every boot (§3/PLAN §3) is
   the *entire* effective environment after any update; nothing persists in NVRAM/SD
   between updates.
2. **`dd if=/media/fat/linux/uboot.img of=/dev/mmcblk0p2` (or `p3` on the "old layout,"
   detected by whether `/dev/mmcblk0p3` exists as a block device)** raw-writes whatever
   `uboot.img` we shipped directly onto the boot partition, unconditionally. **Whatever we
   put in `files/linux/uboot.img` gets flashed to every single user who updates**, with
   zero version negotiation, zero rollback safety net at this layer (rollback works by
   flashing the *other* db's `uboot.img` over it — same one-way `dd`, just triggered from
   the other direction, see §11).

### Hard requirement on P4.4 (already stated in PLAN §8, now with the exact reference values)

Because v1 keeps U-Boot byte-identical to stock (PLAN §8), P4.4's release job **must**
assert our shipped `uboot.img` hashes identically to the stock one before it goes anywhere
near a release asset. Reference values, computed this session directly from
`work/extracted/files/linux/uboot.img` (matches `docs/reference-materials.md`'s
previously recorded SHA-256 byte-for-byte):

| | Value |
|---|---|
| Size | 515,141 bytes |
| MD5 | `c97c70b44bb40d2b238e04dadc4a6a98` |
| SHA-256 | `e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64` |

`docs/reference-materials.md` only recorded the SHA-256 for this file; the MD5 above is
newly computed in this task and should be folded into that file's table when P0.9
consolidates findings.

---

## 9. The multi-db rule: what "first wins" actually means

The warning text, verbatim, and the winning rule:

```python
def _update_linux_impl(self, dbs: list[DbEntity]) -> None:
    for db in dbs:
        if db.linux is not None:
            self._linux_descriptions.append({'id': db.db_id, 'args': db.linux})

    linux_descriptions_count = len(self._linux_descriptions)
    if linux_descriptions_count == 0:
        return

    if linux_descriptions_count > 1:
        ignored_ids = ', '.join(ignored['id'] for ignored in self._linux_descriptions[1:])
        self._update_output.warning('linux_multiple_dbs', f'Too many databases try to update linux. Only 1 can be processed. Ignoring: {ignored_ids}')

    description = self._linux_descriptions[0]
```
[`linux_updater.py#L51-68`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/linux_updater.py#L51)

So "first" is unambiguous at this layer: index 0 of `self._linux_descriptions`, built by
iterating `dbs` **in the order that argument arrives**. The literal printed warning
(`HumanUpdateOutput.warning` just prints the message verbatim,
`src/downloader/update_output.py#L225-226`) names every *losing* db by id — this is the
diagnostic a support thread should ask users to paste, since it tells you exactly which
db won without guessing.

**The question the task brief demands an answer to, not an assumption, is: what
determines the order of `dbs`?** Tracing it fully:

### 9.1 — `dbs` is `install_box.installed_dbs()`

```python
if self._config['update_linux']:
    self._linux_updater.update_linux(install_box.installed_dbs())
```
[`src/downloader/full_run_service.py#L182-183`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/full_run_service.py#L182)

```python
def installed_dbs(self) -> list[DbEntity]: return self._installed_dbs
```
[`src/downloader/online_importer.py#L915`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/online_importer.py#L915)

### 9.2 — `_installed_dbs` is filled in **job-completion order**, not push order

```python
for db_job in report.get_completed_jobs(ProcessDbMainJob):
    box.add_installed_db(db_job.db, db_job.config, db_job.db_hash, db_job.db_size)
```
[`online_importer.py#L341-342`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/online_importer.py#L341)
— `report.get_completed_jobs(...)` returns `self._jobs_completed[job_class.type_id]`
(`src/downloader/jobs/reporters.py#L260`), a list appended to as each `ProcessDbMainJob`
across *all* configured databases finishes. The jobs are executed by a `JobSystem` running
a **`ThreadPoolExecutor`** with `max_threads` concurrent workers
(`src/downloader/job_system.py#L61`, `#L114-131` — `_execute_with_threads` is used
whenever `max_threads > 1`), where `max_threads` comes from the config's
`downloader_threads_limit`, **default 6** (`src/downloader/config.py#L160`,
`ConfigMisterSection`/`default_config()`). Each database's own processing chain — fetch
its `db_url`, parse, mix with local store, then `ProcessDbMainJob` — runs independently and
concurrently with every other configured database's chain:

```python
for pkg in db_pkgs:
    transfer_job = make_transfer_job(pkg.section['db_url'], {}, True, pkg.db_id, priority=True)
    transfer_job.after_job = OpenDbJob(transfer_job=transfer_job, section=pkg.db_id, ...)
    jobs.append(transfer_job)
```
[`online_importer.py#L91-106`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/online_importer.py#L91)
— every configured database's descriptor fetch is pushed together as an equal-priority
job. And critically, `ProcessDbMainJob` — the job whose *completion* is what gets recorded
into `installed_dbs()` — runs **right after** a db's descriptor has been fetched, parsed,
and merged with the local store, and **before** any of that db's *referenced files* are
downloaded:
```python
def _operate_on_impl(self, job: ProcessDbMainJob) -> WorkerResult:
    ...
    if db.zips:
        ... # push zip-processing jobs
    else:
        index_job = ProcessDbIndexJob(db=db, ..., index=Index(files=db.files, folders=db.folders), ...)
        next_jobs = [index_job]
    return next_jobs, None
```
[`src/downloader/jobs/process_db_main_worker.py#L44-88`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/jobs/process_db_main_worker.py#L44)
— it *returns* (completes) having only enumerated what needs doing; it does not wait for
file downloads to finish. **So "first" is a race won by whichever database's own
`db_url` (its db.json / db.json.zip document) fetches and parses fastest — not by how
many files that database catalogs, and not by its textual position in downloader.ini.**

### 9.3 — `default_db_id` reorders the *push*, not the *finish*

There is a sorting step, but it only affects what order jobs are **submitted**, which
under 6-way concurrency does not guarantee finish order:

```python
def sorted_db_sections(config: Config) -> list[tuple[str, ConfigDatabaseSection]]:
    result = []
    first = None
    for db_id, db_section in config['databases'].items():
        if db_id == config['default_db_id']:
            first = (db_id, db_section)
        else:
            result.append((db_id, db_section))
    if first is not None:
        result = [first, *result]
    return result
```
[`src/downloader/db_utils.py#L37-48`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/db_utils.py#L37),
used at
[`full_run_service.py#L132`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/full_run_service.py#L132)
(`db_sections = sorted_db_sections(self._config)`) to build the `db_pkgs` list that
`download_dbs_contents` consumes (`full_run_service.py#L145,148`). `default_db_id`
defaults to `DISTRIBUTION_MISTER_DB_ID` (`"distribution_mister"`) —
[`config.py#L169`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/config.py#L169)
— and is only overridable via the `DEFAULT_DB_ID` **environment variable**
(`config_reader.py#L150`: `config['default_db_id'] = self._valid_db_id(K_DEFAULT_DB_ID,
self._env['DEFAULT_DB_ID'])`), which is not exposed as any `downloader.ini` key
(confirmed: `ConfigMisterSection`'s field list, parsed in `_parse_mister_section`,
`config_reader.py#L339-364`, has no `default_db_id` entry at all).

**Meaning:** on every normal MiSTer setup, `distribution_mister` — if configured — is
*always pushed first* into the job queue, regardless of where its `[distribution_mister]`
section physically sits in `downloader.ini`. But because all per-db fetch jobs run
concurrently and `ProcessDbMainJob` fires as soon as each db's own (small) descriptor is
parsed, **push order does not determine which one's `ProcessDbMainJob` completes first.**

### 9.4 — Correction to the naive reading of PLAN §10 / the verification doc

Both PLAN §10 and `docs/verification/stock-release-20250402.md` state the rule as "first
wins" without specifying the mechanism, which invites the natural (and wrong) assumption
that "first" means "first `[section]` in `downloader.ini`," and that ordering our section
above or below `[distribution_mister]` is what decides the outcome. **It is not.** Section
order in `downloader.ini` has no bearing on which db's `ProcessDbMainJob` finishes first,
because `sorted_db_sections` already overrides it (moving `distribution_mister` to the
front of the *push* order) and, more fundamentally, because completion is a concurrent
race rather than a queue-order guarantee. This is the correction this task was asked to
surface if found — flagging it for `PLAN.md`/`TASKS.md` at P0.9.

**What actually, reliably favors us in practice — and why it's still the right design
target:** `ProcessDbMainJob`'s completion time is dominated by how long it takes to fetch
and parse **that database's own document**. `Distribution_MiSTer`'s `db.json.zip` is a
multi-thousand-entry community catalog (megabytes, compressed). A db.json whose only job
is carrying our `linux` key — per §1, validly just `db_id` + `timestamp` + empty
`files`/`folders` + `linux` — is on the order of a few hundred bytes. In virtually every
real network condition, fetching and JSON-parsing a sub-kilobyte document finishes before
fetching and unzipping+parsing a multi-megabyte one, independent of thread-pool
scheduling nondeterminism. **This is an emergent, empirical property of relative payload
size — not a guarantee the source code gives you** — but it is the actual, correct,
sourced basis for a design rule: **keep our db.json minimal, deliberately, forever.** If
future revisions ever grow our db.json to also manage real `files`/`folders` (e.g. to
distribute companion scripts through the same db), that would erode the very speed
advantage this section documents, and should be done via a **second**, separate db.json
that does *not* carry the `linux` key, specifically to keep the `linux`-carrying db tiny.

### 9.5 — The exact, copy-pasteable `downloader.ini` incantation

Because ordering doesn't determine the winner, the primary recommendation is the
simplest one: use the Downloader's own **drop-in database** mechanism so onboarding never
requires editing the user's existing `downloader.ini` at all.

```python
def _discover_fs_drop_in_files(self, config_path: str) -> list[str]:
    config_dir = str(Path(config_path).parent)
    d_dir = os.path.join(config_dir, FOLDER_downloader)   # FOLDER_downloader = 'downloader'
    d_files = [f for f in glob.glob(os.path.join(d_dir, '*.ini')) if _is_eligible_drop_in(f)] if os.path.isdir(d_dir) else []
    star_files = [f for f in glob.glob(os.path.join(config_dir, 'downloader_*.ini')) if _is_eligible_drop_in(f)]
    return sorted(d_files) + sorted(star_files)
```
[`src/downloader/config_reader.py#L253-266`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/config_reader.py#L253),
loaded from `_load_drop_in_databases` (`config_reader.py#L216-251`) — every `*.ini` file
inside `/media/fat/downloader/`, plus every `/media/fat/downloader_*.ini`, is
auto-discovered and each of its sections is registered as an additional database, with two
restrictions enforced by raising `InvalidConfigParameter`: a drop-in **cannot** define a
`[MiSTer]` section (global settings stay in the base ini) and **cannot** define
`[distribution_mister]` (`config_reader.py#L236-240`) — any other section id, ours
included, is fine.

**The one-file onboarding (recommended):** ship this as
`/media/fat/downloader_mister_linux_modernization.ini` (or
`/media/fat/downloader/mister_linux_modernization.ini` — either glob matches):

```ini
[mister_linux_modernization]
db_url = https://<org>.github.io/<repo>/db.json
```

That's the entire file. No edit to the stock `downloader.ini` at all. `db_url` is the
only field `_parse_database_section` requires
(`config_reader.py#L299-304`: `if db_url is None: raise InvalidConfigParameter(...)`) —
`description`/`filter` are optional (`#L306-317`). The section name must equal the `db_id`
inside our published db.json, case-insensitively (`db_entity.py#L46-47`).

**The alternative (manual edit),** if a user prefers a single file: add the same
`[mister_linux_modernization]` block anywhere inside their existing
`/media/fat/downloader.ini` — position relative to `[distribution_mister]` is, per §9.4,
irrelevant to the outcome; document this explicitly so users don't waste time
experimenting with section order.

**Verifying which db actually won, for support purposes:** the printed
`linux_multiple_dbs` warning (§9, top) names every losing db id — ask users pasting logs
to search their Downloader log
(`Scripts/.config/downloader/<mode>.log`, templated at
[`constants.py#L82`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/constants.py#L82))
for that line. For deliberate, deterministic single-db testing (CI, or a maintainer
diagnosing a report), the Downloader ships a `--run-only <db_id>` CLI mode that filters to
exactly the named database(s), bypassing the race entirely:
```python
commands.add_argument('--run-only', nargs='+', dest='run_only_db_ids', help='run Downloader only for the listed database IDs')
```
[`src/downloader/main.py#L165`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/main.py#L165)
— e.g. `Downloader --run-only mister_linux_modernization` for a controlled test/rollback
run that can't race against `distribution_mister` at all. Useful for P4.5's CI
self-check and for support-thread triage; not part of normal end-user onboarding.

---

## 10. Failure handling and atomicity

Overall shape: **the update is not transactional.** Each phase has its own, inconsistent
level of care about propagating failure, and the tool's own author clearly knew the flash
phase was the dangerous one — the phase-start message says so outright:

```python
elif phase == 'flash':
    self._logger.print("======================================================================================")
    self._logger.print("Hold your breath: updating the Kernel, the Linux filesystem, the bootloader and stuff.")
    self._logger.print("Stopping this will make your SD unbootable!")
    self._logger.print()
    self._logger.print("If something goes wrong, please download the SD Installer from")
    self._logger.print(self._linux_recovery_url)
    self._logger.print("and copy the content of the files/linux/ directory in the linux directory of the SD.")
    self._logger.print("Reflash the bootloader with the SD Installer if needed.")
```
[`src/downloader/update_output.py#L196-206`](https://github.com/MiSTer-devel/Downloader_MiSTer/blob/915315668b9460b0fcdfc728be8254fe698c479f/src/downloader/update_output.py#L196)
— note `self._linux_recovery_url` is literally **whichever db's `url` won the race**
(set in `linux_update_started`, `update_output.py#L182-183`), so a broken update
recommends the winning db's own archive URL as the recovery source — the tool's own
built-in guidance already assumes manual, physical (SD-card-out) recovery is the fallback
for a bad flash. **This should be a direct citation for P4.8's rollback/recovery runbook**,
not an invented one.

### Per-phase failure behavior, each traced to source

| Phase | On failure | State left behind | Data at risk |
|---|---|---|---|
| `fetch_image` | `fetch_file` retries 3× then errors (`linux_updater.py#L88-90`) | Nothing written yet under `/media/fat/linux/` | None — safest phase |
| `fetch_7z` | Same retry/hash/size path (`#L93-98`); or `gunzip`/existence failure (`#L106-116`) | At worst a corrupt `/media/fat/linux/7za.gz` left behind if `gunzip` itself fails after download succeeded — cleaned up by `unlink` on the next attempt's re-fetch | None to the active system; `7za` un-usability blocks *future* updates until fixed |
| `extract` | Explicit `RET_CODE`/`exit $RET_CODE` discipline (§5) — `result.returncode` is trustworthy | `/media/fat/linux.7z` deleted either way; `/media/fat/linux.update` cleaned up on failure | None — active `linux.img` untouched |
| `user_files` | Mount/copy/unmount failures each explicitly checked and `return False` propagated (§6) | New image may be left **mounted** if the copy loop's `break` path is hit before the `umount` call is reached — **re-read `_restore_user_files`: the `unmount_cmd` runs unconditionally after the copy loop regardless of `copy_error`, so the temp mount is always cleaned up; only the *new* image's content may be a partial mix of the six files (see §6's partial-restore note)** | Active `linux.img` untouched either way — update aborts before the flash phase |
| `flash` | **See below — this is the one genuine gap.** | Potentially inconsistent: `files/linux/*` already replaced, `updateboot` possibly only partially executed, reboot flag possibly set regardless | **Highest risk phase**, exactly as the tool's own "hold your breath" message says |

### The flash-phase error-masking gap (new finding — not stated in the verification doc)

The flash script (quoted in full in §7) has **no `set -e`, no per-command exit-code
capture, and no final `exit $RET_CODE`** — contrast this directly with the extract
script three subprocess calls earlier in the same file, which explicitly threads
`RET_CODE` through every branch and ends `exit $RET_CODE` (§5). In a plain POSIX shell
script with commands separated only by newlines (no `&&`/`||`/explicit `if`), **each
line runs regardless of the previous line's exit status**, and the script's own exit
status is simply that of its **last command** — here, `touch
/tmp/downloader_needs_reboot_after_linux_update`, which will succeed in essentially every
circumstance (writing one file to a writable tmpfs).

Practical consequence, read directly off the script: if `mv`, `rsync`, or
`/media/fat/linux/updateboot` itself fails partway (disk full, `dd` I/O error inside
`updateboot`, `rsync` interrupted), **the script still reaches the final `mv -f
linux.img.new linux.img` and the final `touch`**, and `result.returncode` will almost
always be `0` — `_run_subprocesses` will call `self._update_output.linux_update_completed()`
(`linux_updater.py#L172-173`), **report success**, and the reboot flag will be set,
**even though the update may have only partially applied.** Concretely: `updateboot`
already ran unconditionally before the final `mv`, so a `uboot.img` flash could fail
mid-`dd` (e.g. power loss, a locked/busy block device) and the tool would still report
"linux update completed" and schedule a reboot. This does **not** contradict A8/PLAN §8's
requirement that our v1 `uboot.img` be byte-identical to stock (that requirement stands
regardless), but it means **the Downloader's own success/failure signal cannot be trusted
to detect a bad flash** — a fact P4.4's own testing and P4.8's troubleshooting guidance
both need to state plainly, because "the update said it worked" is not evidence that it
did. The only reliable post-update check is what actually boots.

Additionally: `LinuxUpdater.needs_reboot()` only checks whether the flag **file exists**
(`linux_updater.py#L218-219`); it cannot distinguish "flag set because the update
genuinely completed" from "flag set because the script reached its last line regardless
of an earlier failure."

### Failure is not fatal to the overall Downloader process, and is not exit-code-visible

`linux_update_failed` only prints a message (`update_output.py#L209-220`); it does not
raise, does not set any config/exit-code state, and `_run_impl` does not inspect
`update_linux()`'s return value at all (`update_linux` returns `None`,
`full_run_service.py#L182-183`). A failed linux update therefore does **not** by itself
change the overall Downloader process's exit code — only the printed text distinguishes
success from failure. Any monitoring/automation built around this (e.g. a future CI
smoke-test of the published db.json, per P4.5) must scan output/log text, not rely on the
process exit code, to detect a linux-update failure.

Separately, a genuinely malformed `linux` dict (missing key) would raise
`KeyError`/`TypeError` inside `_update_linux_impl`, uncaught locally, but **is** caught by
`main.py`'s top-level handler (`main.py#L87-93`: prints "unexpected" + full traceback,
returns exit code 1) — so a bad publish from our own pipeline surfaces as a whole-run
failure with a traceback, not a silent skip. This is the concrete failure mode P4.5's
"schema self-check against a vendored copy of the Downloader's expectations" is there to
prevent.

---

## 11. Worked example

### 11.1 — Ground truth: reproducing the official entry exactly

As a cross-check that every field above is understood correctly (not just asserted), here
is the **actual, currently-live** `Distribution_MiSTer` `linux` entry, reproduced from
PLAN §10 and independently re-verified this session:

```json
"linux": {
  "hash": "8dc3acae7d758a80a363fbd7ad31d95d",
  "size": 93727644,
  "url": "https://raw.githubusercontent.com/MiSTer-devel/SD-Installer-Win64_MiSTer/b8531c7848526d9a8227841923cc4a493cb6e631/release_20250402.7z",
  "version": "250402"
}
```

Verified this session: `md5sum work/release_20250402.7z` → `8dc3acae7d758a80a363fbd7ad31d95d`
(byte-exact match), file size 93,727,644 bytes (byte-exact match). `version[-6:]` is
`"250402"`, matching the stock rootfs's baked-in `/MiSTer.version` content exactly
(`work/imgroot/MiSTer.version` = `250402`, 6 bytes, no trailing newline). This is the
entry that will **stop** applying (§3) the moment a running system's `/MiSTer.version`
already reads `250402`.

### 11.2 — Our project's future entry (illustrative; P4.4/P4.5 fill in real values)

A complete, schema-valid db.json for this project (`<ORG>`/`<REPO>`/date placeholders —
everything else, including the object shape, is exactly what §1 requires):

```json
{
  "db_id": "mister_linux_modernization",
  "timestamp": 1799712000,
  "files": {},
  "folders": {},
  "linux": {
    "hash": "REPLACE_WITH_MD5_OF_release_YYYYMMDD.7z",
    "size": 00000000,
    "url": "https://github.com/<ORG>/<REPO>/releases/download/YYYYMMDD/release_YYYYMMDD.7z",
    "version": "YYMMDD"
  }
}
```

Required by §1: `db_id` (must equal the `downloader.ini`/drop-in section name,
lower-cased), `timestamp` (int; publish-time epoch seconds is fine), `files`/`folders`
(empty dicts are valid and, per §9.4, deliberately kept empty to preserve the "small
db.json wins the race" property). `linux.hash` is the MD5 of the **whole** `.7z` (§2),
`linux.size` its exact byte count, `linux.url` a direct download link (a GitHub Release
asset URL, matching G6's "GitHub Release assets, never committed"), `linux.version`
whose **last 6 characters** must exactly equal (byte-for-byte, no whitespace, §3) the
`/MiSTer.version` baked into that same release's `linux.img` by `post-build.sh` (P2.6).

### 11.3 — The onboarding `downloader.ini` (or drop-in)

Per §9.5, the recommended file is `/media/fat/downloader_mister_linux_modernization.ini`:

```ini
[mister_linux_modernization]
db_url = https://<org>.github.io/<repo>/db.json
```

placed on the SD card alongside the existing `downloader.ini` — no edits to the existing
file. (Equivalently, the same two lines can be appended as a new section inside the
existing `downloader.ini`; per §9.4 the position within that file does not affect which
db wins the race.)

### 11.4 — Rollback procedure, verified from source, with the mechanism stated

1. Delete (or rename to not match `*.ini`) `/media/fat/downloader_mister_linux_modernization.ini`.
2. Re-run the Downloader (`Scripts/update.sh`, or wait for its next scheduled run).
3. With our drop-in gone, `config['databases']` no longer contains our section
   (`config_reader.py#L118-130` only ever sees whatever's left in the base `downloader.ini`
   plus remaining drop-ins) — so `_linux_descriptions` in `_update_linux_impl` has at most
   one entry, contributed by `distribution_mister` alone (§9, top). There is no race left
   to lose: the "Too many databases" branch is never reached
   (`linux_updater.py#L64-66`), and `description = self._linux_descriptions[0]`
   (`#L68`) is unambiguously the official entry.
4. **Why this actually restores the stock image, not just "an older one":** the version
   check is a pure inequality (§3). The currently-running system's `/MiSTer.version` is
   whatever *our* build stamped (by construction, different from the current official
   `YYMMDD`, since we're a different build). The official db's `version[-6:]` is the
   current official `YYMMDD`. These differ, so the inequality holds and the official
   update proceeds — through the **exact same apply flow** documented in §5–§8: `7za t`,
   extract `files/linux/*` from the **official** archive, restore the six user files into
   the **official** new image, `rsync` the official `files/linux/` (replacing our
   `updateboot`/`uboot.img`/etc. with the official ones), run the official `updateboot`
   (re-flashing the **official** `uboot.img` — relevant in general, moot for v1 since ours
   is required to be byte-identical to it anyway, per §8), swap in the official
   `linux.img`, reboot. Rollback is not a special code path — it is the **same update
   mechanism running in the opposite direction**, which is precisely why it's simple and
   why it's trustworthy: it has no more (and no less) atomicity risk than any other
   update (§10 applies symmetrically).
5. Caveat carried over from §10: because the flash phase's own success signal isn't fully
   trustworthy, treat "did rollback actually happen" as "does `/MiSTer.version` now read
   the official `YYMMDD` after reboot," not "did the Downloader print success."

---

## 12. What P4.4/P4.5 must not break — testable assertions

1. **`uboot.img` byte-identical to stock.** Assert `md5sum`/`sha256sum` of the shipped
   `files/linux/uboot.img` equals `c97c70b44bb40d2b238e04dadc4a6a98` /
   `e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64` (§8). Release-blocking.
2. **`/MiSTer.version` is exactly 6 bytes, no trailing whitespace/newline**, and its
   content's last 6 characters equal the db.json `linux.version`'s last 6 characters
   exactly (§3). Test by `wc -c` on the file inside the built image and a string-equality
   check against the value about to be published in db.json, in the same pipeline run
   that produces both.
3. **`linux.hash`/`linux.size` in the published db.json are the MD5/byte-size of the
   exact `.7z` asset the `linux.url` points at** — compute them from the actual uploaded
   release asset, not from a pre-upload local copy, in case anything touches the file in
   transit (§2). Self-check in CI by re-downloading from the published URL and comparing.
4. **The archive extracts cleanly under the pinned `7za`** (MD5
   `ed1ad5185fbede55cd7fd506b3c6c699`, fetched from
   `https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/raw/master/7za.gz`) — run
   `7za t` and the exact `7za x -y <archive> files/linux/* -o<dir>` command from §5 against
   our built archive using that literal binary (under `qemu-arm`), not a modern host `7z`
   (§4). Release-blocking per P4.4's own task text.
5. **`files/linux/` in our archive carries the full auxiliary payload** the rsync step
   depends on (`updateboot`, `MidiLink.INI`, `ppp_options`, `u-boot.txt_example`,
   `_samba.sh`, `_user-startup.sh`, `_wpa_supplicant.conf`, `gamecontrollerdb/` — even
   though it's rsync-excluded, verify it's *absent or harmless* to include —,
   `mt32-rom-data/`, `soundfonts/`, `zImage_dtb`, `uboot.img`) — a missing file here isn't
   caught by any Downloader-side check; it just silently fails to land on
   `/media/fat/linux/` (§7 step 4.2).
6. **The six user-file destinations exist as regular files** at their stock `/etc` paths
   inside the built `linux.img` (§6) — a symlink or missing path here breaks the copy
   silently (`self._file_system.copy` failure, caught, but the workaround is "the user
   loses that one setting," not a hard failure surfaced anywhere obvious).
7. **The built image is mountable read-write** by whatever e2fsprogs/kernel the
   *currently installed* system runs (A9/P2.5) — this is what makes step 3 of §7 possible
   at all; test by mounting the freshly-built `linux.img` with a stock-vintage
   e2fsprogs/kernel, not just our new one.
8. **Published db.json passes `DbEntity` construction** against a vendored copy of
   `db_entity.py` from this pinned commit (or newer) as part of the publish job — given §1's
   finding that `linux`'s own sub-fields are otherwise unchecked, this self-check plus an
   explicit assertion that `hash`/`size`/`url`/`version` are present and correctly typed is
   the only thing standing between a bad publish and every subscribed user's Downloader
   crashing with a traceback (§10) or, worse, silently failing to ever update.
9. **db.json stays minimal**: no non-empty `files`/`folders`/`zips` on the entry that
   carries `linux`, to preserve the §9.4 "wins the completion race because it's small"
   property. If the project ever wants to distribute other files via its own db, do it
   from a second db.json without a `linux` key.
10. **The db_id/section-name pairing is exact**: whatever `db_id` ships in the published
    db.json must equal, case-insensitively, the section name in the example
    `downloader.ini`/drop-in file shown in P4.8's docs, or onboarding fails at
    `DbEntityValidationException` (§1, §9.5) on the user's very first run.
