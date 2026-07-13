# Python & Downloader compatibility (A6)

**Task:** P3.9. **Constraint index:** A6. **Model:** Sonnet.

**Bottom line up front:** the on-device `python3` on the current build is **broken for
Downloader_MiSTer and for "Update All"** (the most widely used community updater) — not
because of a 3.9→3.14 language/stdlib-removal issue, but because the Buildroot `python3`
package has almost every optional C-extension submodule **deselected**, including
`ssl`. Both tools do `import ssl` on their core HTTP path and both were **actually run**
(not just statically inspected) under the real target ARM Python 3.14.5 via
`qemu-arm`, and both crash identically: `ModuleNotFoundError: No module named '_ssl'`.
Once that (and one more: `zlib`) is fixed, the evidence gathered here is that
Downloader's own source is otherwise clean for 3.14 — no removed-stdlib imports, and
100% of its `.py` files byte-compile without error under the real 3.14 compiler.

**Honesty note up front:** Downloader_MiSTer's own automated test suite
(`src/automated_tests.sh` → `test/unit`, `test/integration`, `test/system/quick`,
`test/system/slow`) is **not available to us**. `src/test/` is explicitly gitignored in
the public repo, and `.github/workflows/request_tests.yml` shows the real suite lives in
a **private** repo, run via a `repository_dispatch` to a `${{ secrets.TESTS_REPO }}` we
have no access to. See §1. This is a hard scoping fact discovered during this task, not
an assumption — I looked for a public mirror and found none. In its place, §3 actually
executes Downloader's and Update All's real, unmodified entry points against the real
target interpreter, which is a stronger signal than the unit tests would have given for
*this specific* question (they run on host CPython 3.9 in CI, not under qemu-user on the
target ABI) but does not substitute for their assertions on internal logic.

---

## 1. Downloader's real test suite is not accessible — confirmed, not assumed

- Local clone: `work/Downloader_MiSTer`, `HEAD` = `9153156` (`915315668b9460b0fcdfc728be8254fe698c479f`,
  branch `main`), matching the commit pinned in `docs/downloader-contract.md`. Working
  tree clean.
- `work/Downloader_MiSTer/src/automated_tests.sh` runs
  `python3 -m unittest discover -s test/unit` etc. — but `src/test/` does not exist in
  the checkout.
- `work/Downloader_MiSTer/.gitignore` line 10: `src/test/` — the test tree is
  deliberately excluded from the public repo, not merely absent from this clone.
- `work/Downloader_MiSTer/.github/workflows/request_tests.yml` — on every push to
  `main`, it does *not* run tests in this repo. It fires an authenticated
  `repository_dispatch` (`event_type: test-sha`) to
  `${{ secrets.TESTS_REPO }}` using `${{ secrets.TESTS_TOKEN }}`, i.e. **the real
  suite runs in a separate, private repository we have no credentials for.**
- Confirmed no public repo fills this role: `curl
  https://api.github.com/orgs/MiSTer-devel/repos?per_page=100` lists no
  downloader/test-shaped repo, and `curl
  https://api.github.com/search/repositories?q=org:MiSTer-devel+downloader+test` returns
  `"total_count": 0`.
- Searched all of `work/` for any cached copy of `test/unit` etc. — none found.

**Conclusion: "Downloader suite green on-target-Python" (the task's literal Done-when
clause) cannot be produced. This is reported, not worked around by inventing a
substitute test suite and calling it the same thing.** §3 below is what was actually run
instead, and is clearly labeled as such throughout.

---

## 2. How target Python was run under qemu-user (exact commands)

No rebuild was performed. Everything below runs against the existing
`output/target/usr/bin/python3.14` (ELF32 ARM, EABI5, hard-float, `armv7l`) from the
current build.

### 2.1 Chroot vs `-L` sysroot-prefix — what was actually used and why

`sudo`/root is not available in this environment (no passwordless sudo), so a real
`chroot(2)` was not possible. Per the task's own fallback instruction ("invoke `qemu-arm
… python3.14` directly with the right library path"), and consistent with the precedent
already in this repo (`scripts/inventory/gen-busybox.sh`, `docs/abi-contract.md` §2.4 use
exactly this pattern for the stock `MiSTer` binary), I used QEMU user-mode's `-L`
sysroot-prefix instead of a real chroot:

```console
$ qemu-arm -L output/target output/target/usr/bin/python3.14 --version
Python 3.14.5
```

`-L` makes qemu-arm resolve the ELF interpreter (`/lib/ld-linux-armhf.so.3`) and all
absolute-path opens the guest makes (library search, `/usr/lib/python3.14/...` stdlib
imports, `/etc`, `/tmp` etc.) against `output/target` first. This is **not** a real
`chroot` — no mount namespace, no root — but it is sufficient to run the actual target
ARM binary against its actual target library/stdlib tree, which is what matters for an
ABI-compatibility question. (`binfmt_misc` on this host also has `qemu-arm` registered
with the `F` "fix binary" flag, so a real `chroot` — if root were available — would not
even need `qemu-arm-static` copied into `output/target/usr/bin/` first; noted for anyone
re-running this with root.)

### 2.2 Proof this is really the target 3.14.5 ARM interpreter, not the host's

```console
$ qemu-arm -L output/target output/target/usr/bin/python3.14 -c \
    "import sys,platform; print(sys.version); print(platform.machine()); print(platform.architecture())"
3.14.5 (main, Jun 16 2026, 21:01:40) [GCC 14.3.0]
armv7l
('32bit', 'ELF')

$ python3 --version        # host, for contrast
Python 3.14.4
```

Different patch version (3.14.5 target vs 3.14.4 host at time of writing) and a 32-bit
`armv7l` platform tag — this is unambiguously the emulated target binary, not the host
interpreter answering by mistake.

One environment-hygiene note: without `-S`/`-I`/`PYTHONNOUSERSITE`, `sys.path` leaked in
`/home/mcf/.local/lib/python3.14/site-packages` (a host path) because `HOME` wasn't
overridden. This never affected any result below (nothing relevant to stdlib C
extensions lives there), but all commands in §3 onward were run with `PYTHONNOUSERSITE=1`
(entry-point tests, to preserve normal `site.py` behavior like the `exit`/`quit`
builtins) or `-S` (bare import/compile checks) to keep the target run honest.

---

## 3. The actual blocker: `_ssl` is not built into target Python — verified by real execution

### 3.1 Root cause in the Buildroot config

`output/.config` (the config that produced the current `output/` build):

```
BR2_PACKAGE_PYTHON3=y
BR2_PACKAGE_PYTHON3_PYC_ONLY=y
# BR2_PACKAGE_PYTHON3_2TO3 is not set
# BR2_PACKAGE_PYTHON3_BERKELEYDB is not set
# BR2_PACKAGE_PYTHON3_BZIP2 is not set
# BR2_PACKAGE_PYTHON3_CODECSCJK is not set
# BR2_PACKAGE_PYTHON3_CURSES is not set
# BR2_PACKAGE_PYTHON3_DECIMAL is not set
# BR2_PACKAGE_PYTHON3_READLINE is not set
# BR2_PACKAGE_PYTHON3_SSL is not set
BR2_PACKAGE_PYTHON3_UNICODEDATA=y
# BR2_PACKAGE_PYTHON3_SQLITE is not set
# BR2_PACKAGE_PYTHON3_PYEXPAT is not set
# BR2_PACKAGE_PYTHON3_XZ is not set
# BR2_PACKAGE_PYTHON3_ZLIB is not set
# BR2_PACKAGE_PYTHON3_ZSTD is not set
# BR2_PACKAGE_PYTHON3_OSSAUDIODEV is not set
```

Every optional submodule is off except `UNICODEDATA`. This reads like the Buildroot
`python3` package's stock defaults were taken as-is rather than chosen against what the
target actually needs to run. `output/target/usr/lib/python3.14/lib-dynload/` (the
actually-built `.so` extension modules) confirms it — 41 files, and `_ssl`, `zlib`,
`_bz2`, `_lzma`, `_sqlite3`, `_curses`, `readline`, `pyexpat`, `_decimal` are **all
absent**.

### 3.2 Downloader_MiSTer's core HTTP path imports `ssl` unconditionally

```
work/Downloader_MiSTer/src/downloader/http_gateway.py:20:  import ssl
work/Downloader_MiSTer/src/downloader/ssl_context.py:19:   import ssl
```

`http_gateway.py` builds `HTTPSConnection` objects directly from `http.client` — this is
Downloader's entire network layer, not an optional feature. `downloader/config.py`
imports `HttpConfig` from `http_gateway.py` at module scope
(`downloader/config.py:28`), and nearly every other module imports `config.py`
transitively — so the `ssl` dependency is not confined to networking code, it poisons
almost the whole package import graph (quantified in §3.4).

### 3.3 Actually running Downloader_MiSTer's real entry point under target 3.14.5

```console
$ cd work/Downloader_MiSTer/src
$ PYTHONNOUSERSITE=1 qemu-arm -L ../../../output/target \
    ../../../output/target/usr/bin/python3.14 __main__.py
No module named '_ssl'


Warning! Your OS version seems to be older than September 2021!
Please upgrade your OS before running Downloader
More info at https://github.com/MiSTer-devel/mr-fusion
$ echo $?
10
```

Exit code **10** is `EXIT_ERROR_WRONG_SETUP` (`work/Downloader_MiSTer/src/downloader/constants.py:239`).
`__main__.py`'s own `except (ImportError, SyntaxError)` handler
(`src/__main__.py:25-34`) catches the `ModuleNotFoundError` from `from downloader.main
import main` and prints a **misleading** diagnostic — it blames OS age ("older than
September 2021"), which is backwards: our OS/kernel is from 2026, five years newer than
that message implies is required; the real cause is a missing Python C extension, not an
old kernel. Anyone hitting this on a real device would be pointed at the wrong problem.

### 3.4 Blast radius: 70 of 88 Downloader submodules fail to import standalone, all at the same choke point

```console
$ for f in downloader/*.py downloader/jobs/*.py downloader/migrations/*.py; do
    mod=$(echo "$f" | sed 's#/#.#g; s#\.py$##')
    qemu-arm -L ../../../output/target ../../../output/target/usr/bin/python3.14 -S -c "import $mod"
  done
```

**70 / 88** fail identically:
```
  File "/usr/lib/python3.14/ssl.py", line 100, in <module>
    import _ssl
ModuleNotFoundError: No module named '_ssl'
```
(via `downloader.config` → `downloader.http_gateway` → `ssl`, for anything that imports
`config`, which is almost everything).

**18 / 88 import cleanly standalone** (pure data/scaffolding modules with no `config`
dependency): `constants`, `db_entity`, `db_options`, `error`,
`external_store_fingerprints`, `fail_policy`, `job_system`, `os_utils`, `path_package`,
`waiter`, `jobs.copy_data_job`, `jobs.errors`, `jobs.fetch_data_job`,
`jobs.fetch_file_job`, `jobs.index`, `jobs.transfer_job`, plus both package `__init__.py`
files. This is only useful as a lower bound on "code that is at least syntactically and
import-time clean" — it is not "code that works," since none of it is exercised beyond
import.

### 3.5 Update_All_MiSTer (the most popular community wrapper) hits the exact same wall

The task brief specifically names `update_all` as a script to smoke-test. `update_all.sh`
(fetched live from `theypsilon/Update_All_MiSTer` — this is not vendored in `work/`)
turns out to be a thin bash launcher that downloads and directly executes a
self-extracting payload; unpacking it (`tail -n +8 | xzcat -d`) shows it is a **Python
zipapp** (PEP 441) with shebang `#!/usr/bin/env python3` — i.e. it runs on whatever
`python3` is on `$PATH`, exactly like Downloader:

```console
$ curl -fsSL https://raw.githubusercontent.com/theypsilon/Update_All_MiSTer/master/dont_download2.sh -o /tmp/dont_download2.sh
$ tail -n +8 /tmp/dont_download2.sh | xzcat -d > /tmp/update_all.pyz
$ head -c 40 /tmp/update_all.pyz
#!/usr/bin/env python3
PK...                          # zip magic follows the shebang line
```

Unzipped and run against the real target interpreter the same way:

```console
$ unzip -q /tmp/update_all.pyz -d /tmp/dd2_zip && cd /tmp/dd2_zip
$ PYTHONNOUSERSITE=1 qemu-arm -L .../output/target .../output/target/usr/bin/python3.14 __main__.py
No module named '_ssl'


Warning! Your OS version seems to be older than September 2021!
Please upgrade your OS before running Update All
More info at https://github.com/theypsilon/ms-fusion
$ echo $?
1
```

Same root cause (`update_all/analogue_pocket/http_gateway.py:2: import ssl`), same
failure mode, different exit code (`1`, Update All's own top-level handler). **Both of
the two Python tools a real user is most likely to run on this image are non-functional
as shipped.**

### 3.6 Why the "fast path" doesn't save you: a hardcoded `/usr/bin/python3.9` check

Downloader ships two execution forms: a Nuitka-compiled standalone binary
(`downloader_bin`, bundles its own runtime) and the pure-Python zipapp fallback tested
above. `downloader.sh` (the on-device launcher, byte-identical between
`work/Downloader_MiSTer/downloader.sh` and the live `main` branch — diffed, zero
differences) decides which one to use with a **literal, hardcoded path check**:

```
work/Downloader_MiSTer/downloader.sh:161:
if [[ -s "${LATEST_BIN_PATH}" && -x /usr/bin/python3.9 ]] ; then
    ...use the compiled downloader_bin fast path...
else
    ...fetch and run dont_download.sh, the ssl-broken zipapp from §3.3...
fi
```

This doesn't check "is there *a* python3", it checks for that **exact literal path**.
Confirmed directly against the built image:

```console
$ test -x output/target/usr/bin/python3.9 && echo EXISTS || echo "DOES NOT EXIST"
DOES NOT EXIST
$ ls -la output/target/usr/bin/python*
lrwxrwxrwx  python -> python3
lrwxrwxrwx  python3 -> python3.14
-rwxr-xr-x  python3.14
```

So on this build, `downloader.sh` **always** falls through to the broken zipapp path —
the compiled-binary fast path is never even attempted, regardless of whether that
compiled binary would itself have worked. (Whether `downloader_bin` — a Nuitka-frozen
binary that bundles its own CPython/OpenSSL — would run fine independent of the system
Python was **not tested**: no ARM build of it was fetched or available locally, and
producing/verifying one is out of scope for this task. It is very plausible it doesn't
share this bug, since Nuitka standalone builds are self-contained; this is a plausibility
argument, not a verified fact, and doesn't change that the currently-shipped launcher
logic won't reach it on this image.)

### 3.7 `zlib` is also missing, and it independently breaks the default database fetch path

`downloader/file_system.py:27` imports `zipfile`; `load_json_from_zip()`
(`file_system.py:673`) and `unzip_contents()` (`file_system.py:583/590`) read `.zip`
files, and `DISTRIBUTION_MISTER_DB_URL` (`downloader/constants.py:31`) —
**the default database Downloader points at** — is
`https://raw.githubusercontent.com/MiSTer-devel/Distribution_MiSTer/main/db.json.zip`, a
DEFLATE-compressed zip (compression is the entire point of shipping `.json.zip` instead
of `.json`). Verified directly, not inferred:

```console
$ python3 -c "
import zipfile
with zipfile.ZipFile('/tmp/deflate_test.zip','w',zipfile.ZIP_DEFLATED) as zf:
    zf.writestr('db.json', '...')"        # built on host, simulating a real deflate zip
$ qemu-arm -L output/target output/target/usr/bin/python3.14 -I -c "
import zipfile
with zipfile.ZipFile('/tmp/deflate_test.zip') as zf:
    zf.read('db.json')"
RuntimeError: Compression requires the (missing) zlib module
```

Plain `zipfile.ZIP_STORED` (uncompressed) archives read/write fine without `zlib` — but
that's not what any real-world `.json.zip` on GitHub is. **This is a second, independent
hard blocker**, distinct from `_ssl`, that would surface immediately after `_ssl` is
fixed.

### 3.8 The fix — exact Buildroot options, and why it should be low-risk

From `work/buildroot/package/python3/Config.in`:

```
config BR2_PACKAGE_PYTHON3_SSL
	bool "ssl"
	select BR2_PACKAGE_OPENSSL
	select BR2_PACKAGE_OPENSSL_FORCE_LIBOPENSSL
	select BR2_PACKAGE_LIBOPENSSL_ENABLE_BLAKE2
	help
	  _ssl module for Python3 (required for https in urllib etc).

config BR2_PACKAGE_PYTHON3_ZLIB
	bool "zlib module"
	select BR2_PACKAGE_ZLIB
	help
	  zlib support in Python3
```

**Both underlying target libraries already exist in the current build** — this isn't
pulling in a new dependency, just wiring Python to what's already there:

```console
$ grep '^BR2_PACKAGE_OPENSSL=y\|^BR2_PACKAGE_LIBOPENSSL=y\|^BR2_PACKAGE_ZLIB=y' output/.config
BR2_PACKAGE_OPENSSL=y
BR2_PACKAGE_LIBOPENSSL=y
BR2_PACKAGE_ZLIB=y
$ find output/target -iname 'libssl.so*' -o -iname 'libcrypto.so*' -o -iname 'libz.so*'
output/target/usr/lib/libssl.so.3
output/target/usr/lib/libcrypto.so.3
output/target/usr/lib/libz.so.1
```

**Recommend enabling, MUST (verified blockers):**
- `BR2_PACKAGE_PYTHON3_SSL=y`
- `BR2_PACKAGE_PYTHON3_ZLIB=y`

**Recommend considering, SHOULD (not proven to block Downloader specifically, but cheap,
and A6 explicitly names "many community scripts" as in scope — none of these were
observed missing in the two tools actually tested, so treat as defensive parity, not
urgent):**
- `BR2_PACKAGE_PYTHON3_BZIP2` — `bz2`, used by some third-party archive-handling scripts.
- `BR2_PACKAGE_PYTHON3_SQLITE` — `sqlite3`, some community tools cache local state in it.
- `BR2_PACKAGE_PYTHON3_XZ` — `lzma`; not needed by Downloader itself (it shells out to
  the pinned `7za` binary for `.7z`, per `docs/downloader-contract.md`, not Python's
  `lzma`), but general-purpose scripts sometimes use `tarfile` with xz.
- `BR2_PACKAGE_PYTHON3_PYEXPAT` — only if some script parses XML; not used by Downloader
  or the sampled community scripts.
- `BR2_PACKAGE_PYTHON3_READLINE` — quality-of-life for anyone using the Python REPL
  interactively over serial/SSH; irrelevant to any script run non-interactively.
- `BR2_PACKAGE_PYTHON3_DECIMAL` — the pure-Python `decimal` fallback already works
  (confirmed, §4.2); this only buys speed via the C accelerator.
- `BR2_PACKAGE_PYTHON3_CURSES` — no observed consumer; stock MiSTer scripts don't seem to
  build TUIs in Python.

I did not make any of these changes — per the task constraints, this is a report for the
orchestrator to apply and rebuild.

---

## 4. What's actually clean: no 3.9→3.14 language/stdlib-removal breakage found

This is the part of A6 that *is* good news, and it was checked by executing the real
3.14 compiler/interpreter, not by reading the diffs between Python release notes.

### 4.1 Zero removed-stdlib imports anywhere in Downloader's source

```console
$ grep -rnE '^\s*(import|from) (distutils|imp|cgi|cgitb|asynchat|asyncore|smtpd|telnetlib|nntplib|uu|xdrlib|sndhdr|ossaudiodev|spwd|nis|crypt|formatter|binhex|mailcap|imghdr|audioop|aifc|chunk|msilib|pipes)\b' \
    downloader/*.py downloader/**/*.py *.py
(no matches)
$ grep -rnE 'collections\.(Mapping|MutableMapping|Sequence|Iterable|Callable|Set|MutableSet)\b' downloader/*.py downloader/**/*.py *.py
(no matches)
```

None of `distutils` (removed 3.12), `imp` (removed 3.12), `cgi`/`cgitb` (removed 3.13),
`asynchat`/`asyncore`/`smtpd` (removed 3.12), or the pre-3.10 `collections.<ABC>`
shortcuts appear anywhere in the codebase.

### 4.2 Every Downloader `.py` file byte-compiles cleanly under the real 3.14 compiler

```console
$ qemu-arm -L output/target output/target/usr/bin/python3.14 -S -m compileall -q -f \
    downloader __main__.py pc_launcher.py debug.py
$ echo $?
0
```

91 files (88 in `downloader/` + `__main__.py`, `pc_launcher.py`, `debug.py`), zero
syntax/compile errors, using the actual target 3.14.5 parser/compiler — not a version
assumption.

### 4.3 `decimal` works fine on the pure-Python fallback

```console
$ qemu-arm -L output/target output/target/usr/bin/python3.14 -I -c "import decimal; print(decimal.Decimal)"
<class 'decimal.Decimal'>
```
Not a blocker even though `BR2_PACKAGE_PYTHON3_DECIMAL` is off — just slower (no `_decimal` C
accelerator). Downloader doesn't appear to use `decimal` regardless (not in the grep list
above); noted only because it's a widely-used module elsewhere.

### 4.4 Full inventory of stdlib import attempts run against the target binary

| Module | Result | Downloader depends on it? |
|---|---|---|
| `ssl` | **FAIL** — `No module named '_ssl'` | Yes, unconditionally (§3.2) — **blocker** |
| `zlib` | **FAIL** — `No module named 'zlib'` | Yes, via `zipfile` DEFLATE (§3.7) — **blocker** |
| `sqlite3` | FAIL — `No module named 'sqlite3'` | No (grepped, not imported) |
| `bz2` | FAIL — `No module named '_bz2'` | No |
| `lzma` | FAIL — `No module named '_lzma'` | No (uses external `7za` instead) |
| `pyexpat` | FAIL — `No module named 'pyexpat'` | No |
| `curses` | FAIL — `No module named 'curses'` | No |
| `readline` | FAIL — `No module named 'readline'` | No (non-interactive) |
| `decimal` | **OK** (pure-Python fallback) | No (not imported) |
| `hashlib` (md5) | **OK** — `_md5` extension present | Yes — used for file hash verification, works |
| `socket` | **OK** | Yes, works |
| `json` | **OK** | Yes, works |
| `zipfile` (`ZIP_STORED` only) | **OK** | Yes — but real-world zips are deflate (§3.7) |

---

## 5. Community-script smoke test

### 5.1 The official curated list is entirely bash

`MiSTer-devel/Scripts_MiSTer` (the repo the on-device Scripts menu actually surfaces,
per `docs/package-manifest.md`'s scope) was fetched via the GitHub API — **every file in
it is a `.sh` script; zero `.py` files.** This substantially narrows A6's real exposure:
the two concrete Python consumers on a stock-shaped MiSTer are Downloader_MiSTer itself
and community add-on tools like Update All / MiSTer_SAM, not the curated Scripts menu.

### 5.2 MiSTer_SAM (`mrchrisster/MiSTer_SAM`) — a popular third-party Python tool, actually run

Fetched live (not vendored in `work/`) — 4 Python files from `.MiSTer_SAM/`:
`MiSTer_SAM_MCP.py` (1067 lines, the main daemon), `MiSTer_SAM_joy.py`,
`MiSTer_SAM_keyboard.py`, `MiSTer_SAM_mouse.py`.

- Grep for removed stdlib modules: none found.
- `compileall -q -f .` under target 3.14: **0 errors**, all 4 files.
- Actually executed under `qemu-arm -L output/target … python3.14`:

  | Script | Result |
  |---|---|
  | `MiSTer_SAM_keyboard.py` | Ran to completion, printed `Keyboard disconnected` (graceful — no keyboard device present in this environment, as expected off-hardware). Exit 0. |
  | `MiSTer_SAM_mouse.py` | Same pattern: `Mouse disconnected`, exit 0. |
  | `MiSTer_SAM_joy.py` | Ran past all imports and startup logic, then `FileNotFoundError` on a config file (`sam_controllers.json`) not present in the ad hoc test directory — an environment artifact of my test setup, not a Python-compat failure; it proves the script imports and executes real logic cleanly on 3.14. |
  | `MiSTer_SAM_MCP.py` | The long-running daemon; ran silently for the full 5s timeout with no crash, no traceback (consistent with an event loop polling for hardware that isn't present in this environment). Inconclusive on functionality, but **no compatibility failure observed**. |

No `ssl`/`zlib`-style blocker in this sample — these scripts use `asyncio`, `configparser`,
`struct`, `subprocess`, `signal`, `glob`, `json`, `os`, `sys`, `threading`, `time`, none
of which are affected by the gaps in §3.

### 5.3 What was not covered

This is a time-boxed sample (2 tools, ~92 files total examined), not an exhaustive
census of the community-script ecosystem the task brief gestures at ("many community
scripts"). Anything beyond Downloader_MiSTer, Update_All_MiSTer, and MiSTer_SAM's 4
Python files was not fetched or tested.

---

## 6. Summary table

| # | Finding | Severity | Verified how | Upstream-fixable or blocker |
|---|---|---|---|---|
| 1 | `_ssl` not built (`BR2_PACKAGE_PYTHON3_SSL` unset) | **Blocker** | Real execution: Downloader `__main__.py` and Update All's `.pyz`, both under real qemu-user target 3.14.5 | Our Buildroot config — not a Downloader bug |
| 2 | `zlib` not built (`BR2_PACKAGE_PYTHON3_ZLIB` unset) | **Blocker** (independent of #1) | Real execution: read of a real DEFLATE zip fails under target 3.14.5 | Our Buildroot config — not a Downloader bug |
| 3 | `downloader.sh` hardcodes `-x /usr/bin/python3.9` to gate the compiled-binary fast path | High — masks/compounds #1, means the broken fallback is always taken on this image | Read of pinned + live `downloader.sh`; confirmed `/usr/bin/python3.9` absent on built rootfs | Downloader's own script; worth an upstream issue, but our python3 version choice (3.14 vs stock's 3.9) is what trips it |
| 4 | Downloader source: no removed-stdlib imports, no deprecated-ABC imports, 100% of files compile clean under real 3.14 compiler | Informational (good news) | Real execution of `compileall` + grep | N/A |
| 5 | `bz2`/`sqlite3`/`lzma`/`pyexpat`/`curses`/`readline`/`_decimal` also not built | Low — not used by Downloader or the sampled community scripts | Real execution: each import attempted individually against target | Config, only if a real consumer turns up |
| 6 | Downloader's own automated test suite is inaccessible (private repo) | Scope limitation, not a code finding | Read of `.gitignore` + `request_tests.yml` + GitHub org search | N/A — cannot be fixed from here |
| 7 | Official `Scripts_MiSTer` has zero Python files | Informational — narrows A6's blast radius | GitHub API listing | N/A |
| 8 | MiSTer_SAM (4 files) — no compat issues found | Informational (good news) | Real execution + compileall | N/A |

---

## 7. Reproduction — exact commands

```bash
# from repo root, branch phase3-parity, existing output/ build, no rebuild
ROOTFS=output/target
PY=$ROOTFS/usr/bin/python3.14

# 1. Prove target identity
qemu-arm -L "$ROOTFS" "$PY" -c "import sys,platform; print(sys.version); print(platform.machine())"

# 2. Reproduce the ssl blocker directly
qemu-arm -L "$ROOTFS" "$PY" -I -c "import ssl"

# 3. Reproduce the zlib blocker directly
qemu-arm -L "$ROOTFS" "$PY" -I -c "import zlib"

# 4. Run Downloader_MiSTer's real entry point (work/Downloader_MiSTer must be present)
cd work/Downloader_MiSTer/src
PYTHONNOUSERSITE=1 qemu-arm -L ../../../$ROOTFS ../../../$PY __main__.py; echo "exit=$?"
cd ../../..

# 5. Compile-check all of Downloader's source under the real 3.14 compiler
qemu-arm -L "$ROOTFS" "$PY" -S -m compileall -q -f \
    work/Downloader_MiSTer/src/downloader \
    work/Downloader_MiSTer/src/__main__.py \
    work/Downloader_MiSTer/src/pc_launcher.py \
    work/Downloader_MiSTer/src/debug.py
echo "exit=$?"

# 6. Fetch + run Update All's real fallback zipapp (network required; not vendored)
curl -fsSL https://raw.githubusercontent.com/theypsilon/Update_All_MiSTer/master/dont_download2.sh -o /tmp/dd2.sh
tail -n +8 /tmp/dd2.sh | xzcat -d > /tmp/update_all.pyz
mkdir -p /tmp/dd2_zip && unzip -oq /tmp/update_all.pyz -d /tmp/dd2_zip
cd /tmp/dd2_zip
PYTHONNOUSERSITE=1 qemu-arm -L "$OLDPWD/$ROOTFS" "$OLDPWD/$PY" __main__.py; echo "exit=$?"
cd "$OLDPWD"

# 7. Confirm /usr/bin/python3.9 is absent on the built rootfs (downloader.sh's gate)
test -x "$ROOTFS/usr/bin/python3.9" && echo EXISTS || echo "DOES NOT EXIST"
```

Environment used: host Ubuntu, `qemu-arm version 10.2.1 (Debian 1:10.2.1+ds-1ubuntu3.1)`,
no root/sudo available (hence `-L` sysroot-prefix rather than a real `chroot`; see §2.1
for why this is equivalent for this question). `binfmt_misc` has `qemu-arm` registered
with the `F` flag, so a real chroot (with root) would not require copying
`qemu-arm-static` into `output/target` first.

---

## 8. Direct answers to the report-back questions

1. **Did Downloader's suite run green under target 3.14.5?** No suite was run — it
   could not be, because it isn't accessible to us (§1: private repo, gitignored
   locally). What *was* run, actually executed under the real target 3.14.5 via
   qemu-user: Downloader's real `__main__.py` entry point (fails, exit 10, `_ssl`
   missing) and a `compileall` pass over all 91 of its source files (100% clean, 0
   errors). Both are real, reproducible results — neither is a substitute for the
   hidden test suite's assertions.
2. **Any hard blockers?** Yes, two, both config gaps not code bugs: `_ssl` missing
   (§3, breaks 100% of network operations, verified by actually running Downloader and
   Update All) and `zlib` missing (§3.7, breaks reading the default
   `db.json.zip`, verified against a real DEFLATE zip). Compounding factor, not itself a
   blocker to fix here: `downloader.sh` hardcodes a check for `/usr/bin/python3.9` (§3.6)
   that will never be true on any build shipping Python 3.14, so the compiled-binary fast
   path is never attempted and the broken fallback always runs.
3. **Buildroot options to enable?** `BR2_PACKAGE_PYTHON3_SSL=y` and
   `BR2_PACKAGE_PYTHON3_ZLIB=y` (both MUST). `BR2_PACKAGE_PYTHON3_BZIP2`,
   `_SQLITE`, `_XZ`, `_PYEXPAT`, `_READLINE`, `_DECIMAL` are SHOULD-consider for general
   community-script parity but were not proven necessary by anything actually tested.
   Underlying libs (`openssl`, `zlib`) are already built into the target (§3.8), so this
   should be a low-risk, localized change. No changes were made — this is a report only.
4. **Actually run vs static analysis:** Actually run under real qemu-user emulation of
   the target 3.14.5 ARM binary: §2 (interpreter identity), §3.3–§3.5 (Downloader's and
   Update All's real entry points), §3.4 (88 individual module-import attempts), §3.7
   (zipfile DEFLATE read against a real fixture), §4.2 (compileall over 91 files), §5.2
   (4 MiSTer_SAM scripts). Static-analysis-only: §4.1 (grep for removed-module imports —
   no execution needed since the result is "absent," and grep is the right tool for an
   absence claim). Explicitly unverified / out of scope: the real Downloader test suite
   (inaccessible, §1); whether the Nuitka-compiled `downloader_bin` binary works
   independent of system Python (plausible, not tested, §3.6); anything beyond the 2
   tools + 4 scripts sampled in §5; actual network I/O against a real HTTPS endpoint with
   `ssl` hypothetically enabled (would require a rebuild, which was out of scope here).
5. **Exact commands:** §7, copy-pasteable from repo root on this same checkout state.
