#!/usr/bin/env python3
"""Vendored re-implementation of `Downloader_MiSTer`'s `DbEntity` validation
contract -- TASKS.md P4.5's mandated "schema self-check ... against a vendored
copy of the Downloader's expectations" (see docs/downloader-contract.md, P0.6).

Pinned reference: `MiSTer-devel/Downloader_MiSTer` @
`915315668b9460b0fcdfc728be8254fe698c479f` (docs/downloader-contract.md's own
pin). Every check below is a line-cited mirror of what `src/downloader/
db_entity.py`'s `DbEntity.__init__` actually does at that commit -- quoted
verbatim in docs/downloader-contract.md §1.

WHY THIS IS A REIMPLEMENTATION, NOT A LIVE FETCH: executing code pulled from a
third-party repo inside CI -- even one pinned by commit SHA -- is a supply-chain
surface this project doesn't need to accept just to validate a JSON shape. The
actual upstream file has already been read and quoted, in full, in
docs/downloader-contract.md §1 (`db_entity.py#L39-72`); this module hand-mirrors
those exact checks so validation is deterministic, offline, and auditable by
diffing this file against the quoted source, not by trusting a network fetch at
CI time.

**If docs/downloader-contract.md's pinned commit ever moves**, re-diff this file
against the new `db_entity.py` by hand and update both the pin comment there and
the checks here together -- see that document's own header for the
re-verification procedure it expects.

Two layers, matching the contract's own two layers:

  1. `validate_db_entity()` -- what `DbEntity.__init__` itself checks
     (docs/downloader-contract.md §1, `db_entity.py#L39-72`): `db_id` / `files`
     / `folders` / `timestamp` presence and type, the case-folded `db_id` vs.
     INI-section-name match, and that `linux`, if present, is a dict. This is
     the *complete* set of checks the real Downloader performs before parsing
     ever reaches `linux`'s own sub-fields.

  2. `validate_linux_entry()` -- **not** an upstream check. The contract's own
     finding (§1, §10, §12 item 8) is that `linux.hash`/`size`/`url`/`version`
     are read completely unchecked, deep inside `LinuxUpdater`, and a wrong
     type there surfaces as an uncaught `KeyError`/`TypeError` on every
     subscribed user's device (caught only by `main.py`'s top-level handler,
     which prints a traceback and exits 1 -- not a graceful skip). This layer
     is this project's own safety net, added because upstream has none.
"""

import re

_MD5_RE = re.compile(r"^[0-9a-f]{32}$")


class DbSchemaError(Exception):
    """Raised on any contract violation -- mirrors `DbEntityValidationException`."""


def validate_db_entity(db_props, section_name):
    """Layer 1: `DbEntity.__init__` (docs/downloader-contract.md §1,
    `db_entity.py#L39-72`).

    `db_props` -- the parsed db.json top-level object.
    `section_name` -- the `downloader.ini` / drop-in section id this db is
    published under (must case-fold-match `db_id`, `db_entity.py#L46-47`).

    Returns `(db_id, linux_or_none)` on success; raises `DbSchemaError` on any
    violation.
    """
    if not isinstance(db_props, dict):
        raise DbSchemaError("db.json root must be a JSON object")

    # db_entity.py#L39-42
    for key in ("db_id", "files", "folders", "timestamp"):
        if key not in db_props:
            raise DbSchemaError(
                f"missing required top-level key {key!r} (db_entity.py#L39-42)"
            )

    # db_entity.py#L46-47: "Section ... does not match database id ... Fix
    # your INI file."
    db_id = str(db_props["db_id"]).lower()
    if db_id != section_name.lower():
        raise DbSchemaError(
            f"db_id {db_id!r} does not case-fold-match section name "
            f"{section_name!r} (db_entity.py#L46-47)"
        )

    # db_entity.py#L48-49
    timestamp = db_props["timestamp"]
    if not isinstance(timestamp, int) or isinstance(timestamp, bool):
        raise DbSchemaError("timestamp must be an int (db_entity.py#L48-49)")

    # db_entity.py#L50-53: files/folders must be dicts, may be empty.
    if not isinstance(db_props["files"], dict):
        raise DbSchemaError(
            "files must be an object (may be empty) (db_entity.py#L50-53)"
        )
    if not isinstance(db_props["folders"], dict):
        raise DbSchemaError(
            "folders must be an object (may be empty) (db_entity.py#L50-53)"
        )

    # db_entity.py#L70-71
    linux = db_props.get("linux", None)
    if linux is not None and not isinstance(linux, dict):
        raise DbSchemaError(
            "linux, if present, must be an object (db_entity.py#L70-71)"
        )

    return db_id, linux


def validate_linux_entry(linux):
    """Layer 2: our own safety net over the four fields `LinuxUpdater` actually
    reads (docs/downloader-contract.md §1's table; §12 item 8). Not an
    upstream check -- see module docstring.
    """
    if not isinstance(linux, dict):
        raise DbSchemaError("linux must be an object")

    # linux_updater.py#L74 / fetch_file_worker.py#L118-128 -- the complete set
    # of sub-fields ever read (docs/downloader-contract.md §1).
    for key in ("hash", "size", "url", "version"):
        if key not in linux:
            raise DbSchemaError(f"linux.{key} is required (docs/downloader-contract.md §1)")

    # §2: MD5 of the whole .7z, lowercase hex, via hashlib.md5().hexdigest().
    h = linux["hash"]
    if not isinstance(h, str) or not _MD5_RE.match(h):
        raise DbSchemaError(
            "linux.hash must be a lowercase 32-hex-character MD5 digest (§2)"
        )

    # §2: exact byte size of the .7z.
    size = linux["size"]
    if not isinstance(size, int) or isinstance(size, bool) or size <= 0:
        raise DbSchemaError("linux.size must be a positive int (byte count, §2)")

    # §1: a direct HTTP(S) URL; fetch_file_worker.py does no scheme validation
    # of its own, but shipping anything else here is certainly a mistake.
    url = linux["url"]
    if not isinstance(url, str) or not url.startswith(("http://", "https://")):
        raise DbSchemaError("linux.url must be a direct http(s) URL (§1)")

    # §1/§3: only the LAST 6 characters are ever read
    # (`linux['version'][-6:]`, linux_updater.py#L74); by convention (and to
    # match /MiSTer.version's own 6-ASCII-digit self-check in post-build.sh)
    # those 6 characters are YYMMDD.
    version = linux["version"]
    if not isinstance(version, str) or len(version) < 6:
        raise DbSchemaError(
            "linux.version must be a string of at least 6 characters -- only "
            "the last 6 are ever read (linux_updater.py#L74, §1)"
        )
    tail = version[-6:]
    if not tail.isdigit():
        raise DbSchemaError(
            f"linux.version's last 6 characters ({tail!r}) are not all "
            "digits -- by convention this must be YYMMDD (§3)"
        )


def validate(db_props, section_name):
    """Run both layers. Returns `(db_id, linux_or_none)`; raises
    `DbSchemaError` on any violation."""
    db_id, linux = validate_db_entity(db_props, section_name)
    if linux is not None:
        validate_linux_entry(linux)
    return db_id, linux
