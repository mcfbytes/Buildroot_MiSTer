#!/usr/bin/env python3
"""gen-db-json.py -- generate the project's `db.json` (TASKS.md P4.5).

Called by `.github/workflows/publish-db.yml`; kept standalone/testable so it
can also be run by hand against any already-published GitHub Release, or
exercised in isolation with `--asset-file`/`--hash`+`--size` for a fully
offline dry run.

## Schema

Per `docs/downloader-contract.md` §1 (P0.6, itself line-cited against
`Downloader_MiSTer`'s `src/downloader/db_entity.py`/`linux_updater.py` at the
pinned commit), the smallest valid, schema-correct db.json this project can
publish is:

    {
      "db_id": "mister_linux_modernization",
      "timestamp": <int, publish-time epoch seconds>,
      "files": {},
      "folders": {},
      "linux": {
        "hash":    "<lowercase 32-hex MD5 of the release_YYYYMMDD.7z asset>",
        "size":    <int, exact byte size of that same asset>,
        "url":     "<direct https:// URL to that asset>",
        "version": "<string whose LAST 6 characters are read; YYMMDD>"
      }
    }

`files`/`folders` are DELIBERATELY kept empty (not exposed as flags) --
docs/downloader-contract.md §9.4/§12 item 9: this db's job completion time,
and therefore whether it wins the Downloader's multi-db "first one to finish
parsing wins" race against `Distribution_MiSTer`'s multi-megabyte catalog, is
dominated by how small this document is. Growing it defeats the one property
that makes it win.

## VERSIONING (ADR 0018 -- Accepted; see docs/db-json-versioning.md)

`linux.version`'s last 6 characters are compared, by strict string inequality,
against the RUNNING system's `/MiSTer.version` (linux_updater.py#L73-76). So the
two must be EQUAL for a device that is already up to date, and DIFFERENT for one
that is not. Both halves matter, and getting either wrong produces a bad failure:

  * same version for two different releases -> the new one is never offered;
  * a version that never equals what the image bakes in -> the device looks
    outdated on EVERY Downloader run, and re-flashes forever.

ADR 0018 makes both hold by giving the two values a single source of truth: the
TAGGED COMMIT's date. `release.yml` derives MISTER_VERSION from it, post-build.sh
bakes exactly that into `/MiSTer.version`, and it also names the archive
`release_YYYYMMDD.7z`. publish-db.yml then recovers the same 6-digit YYMMDD from
that filename and passes it here as `--version`. Archive name, `/MiSTer.version`,
and `db.json`'s `version` are therefore the same value by construction.

This deliberately does NOT come from SOURCE_DATE_EPOCH, which the defconfig pins
to a constant for reproducibility -- every release would otherwise claim the same
version. Nor from `publishedAt`: that is the moment a human clicked "publish",
which can differ from the build date and would break the equality above.

`--published-at` remains supported for ad-hoc/manual use and is how this was done
before ADR 0018, but it is NOT how releases are versioned. Prefer `--version`.

`linux.hash`/`linux.size` are computed from the actual downloaded release
asset (`--asset-file`), never from a pre-upload local build copy
(docs/downloader-contract.md §12 item 3) -- the workflow that calls this
script downloads the asset fresh from the published GitHub Release URL for
exactly this reason.
"""

import argparse
import datetime
import hashlib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db_entity_contract import DbSchemaError, validate  # noqa: E402

DEFAULT_DB_ID = "mister_linux_modernization"

# Streamed MD5 over the whole file, same idiom as the Downloader's own
# hash_file() (docs/downloader-contract.md §2, file_system.py#L659-666) --
# read in fixed-size chunks so this doesn't load a ~90 MB archive into memory
# at once.
_CHUNK = 1024 * 1024


def md5_and_size(path):
    """Return (lowercase hex MD5, byte size) of the file at `path`."""
    h = hashlib.md5()
    size = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(_CHUNK)
            if not chunk:
                break
            h.update(chunk)
            size += len(chunk)
    return h.hexdigest(), size


def yymmdd_from_iso8601(iso_ts):
    """Parse an ISO-8601 timestamp (e.g. GitHub's release `publishedAt`,
    `2026-07-13T22:04:11Z`) and return its UTC calendar date as a 6-digit
    `YYMMDD` string -- the same convention `/MiSTer.version` and stock's own
    `version` field both use (docs/downloader-contract.md §1, §3;
    post-build.sh).
    """
    ts = iso_ts.strip()
    # datetime.fromisoformat() before Python 3.11 doesn't accept a trailing
    # 'Z' -- normalize it to an explicit UTC offset first.
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    dt = datetime.datetime.fromisoformat(ts)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    dt = dt.astimezone(datetime.timezone.utc)
    return dt.strftime("%y%m%d")


def build_db_json(db_id, timestamp, linux_hash, linux_size, linux_url, linux_version):
    """Assemble the full db.json document. `files`/`folders` are always
    empty -- see the module docstring for why that is load-bearing, not
    incidental."""
    return {
        "db_id": db_id,
        "timestamp": timestamp,
        "files": {},
        "folders": {},
        "linux": {
            "hash": linux_hash,
            "size": linux_size,
            "url": linux_url,
            "version": linux_version,
        },
    }


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--db-id",
        default=DEFAULT_DB_ID,
        help=f"db_id / downloader.ini section name (default: {DEFAULT_DB_ID!r})",
    )
    ap.add_argument("--out", default="db.json", help="output path (default: db.json)")
    ap.add_argument(
        "--timestamp",
        type=int,
        default=None,
        help="db.json top-level `timestamp`, unix epoch seconds (default: now). "
        "NOT the update-detection signal -- DbEntity only requires it be an "
        "int (docs/downloader-contract.md §1); purely informational.",
    )
    ap.add_argument("--url", required=True, help="direct https:// URL to the release_YYYYMMDD.7z asset")

    ver_group = ap.add_mutually_exclusive_group(required=True)
    ver_group.add_argument(
        "--version",
        help="raw linux.version string, used as-is (only its last 6 characters "
        "are ever read by the Downloader)",
    )
    ver_group.add_argument(
        "--published-at",
        help="ISO-8601 release publish timestamp (e.g. GitHub's `publishedAt`); "
        "version is derived as its UTC date, YYMMDD -- see the module "
        "docstring for why this is release-date-driven, not image-version-driven",
    )

    hash_group = ap.add_mutually_exclusive_group(required=True)
    hash_group.add_argument(
        "--asset-file",
        help="path to the downloaded release_YYYYMMDD.7z; hash and size are "
        "computed directly from it (docs/downloader-contract.md §12 item 3)",
    )
    hash_group.add_argument(
        "--hash",
        help="precomputed lowercase MD5 hex digest (must be paired with --size; "
        "mainly for tests -- prefer --asset-file for a real publish)",
    )
    ap.add_argument("--size", type=int, help="precomputed byte size (paired with --hash)")

    ap.add_argument(
        "--section",
        default=None,
        help="section name used for the self-check's db_id match (default: --db-id)",
    )
    ap.add_argument(
        "--no-self-check",
        action="store_true",
        help="skip the internal schema self-check before writing (for deliberately "
        "producing invalid output in tests -- never use for a real publish)",
    )
    ap.add_argument("--indent", type=int, default=2, help="JSON indent (default: 2)")
    args = ap.parse_args(argv)

    if bool(args.hash) != bool(args.size is not None):
        ap.error("--hash and --size must be given together")

    if args.asset_file:
        asset_path = Path(args.asset_file)
        if not asset_path.is_file():
            ap.error(f"--asset-file {args.asset_file!r} does not exist")
        linux_hash, linux_size = md5_and_size(asset_path)
    else:
        linux_hash, linux_size = args.hash.lower(), args.size

    if args.version:
        version = args.version
    else:
        try:
            version = yymmdd_from_iso8601(args.published_at)
        except ValueError as exc:
            ap.error(f"--published-at {args.published_at!r} is not a valid ISO-8601 timestamp: {exc}")

    timestamp = args.timestamp if args.timestamp is not None else int(time.time())

    doc = build_db_json(args.db_id, timestamp, linux_hash, linux_size, args.url, version)

    if not args.no_self_check:
        section = args.section or args.db_id
        try:
            validate(doc, section)
        except DbSchemaError as exc:
            print(
                f"error: generated db.json fails its own schema self-check: {exc}",
                file=sys.stderr,
            )
            return 1

    text = json.dumps(doc, indent=args.indent, sort_keys=True) + "\n"
    Path(args.out).write_text(text)
    print(
        f"wrote {args.out}: db_id={args.db_id!r} linux.version={version!r} "
        f"linux.hash={linux_hash} linux.size={linux_size} linux.url={args.url!r}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
