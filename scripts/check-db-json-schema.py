#!/usr/bin/env python3
"""check-db-json-schema.py -- CI/local self-check for a generated db.json
(TASKS.md P4.5's mandated "schema self-check").

Why this exists as a SEPARATE step from generation (scripts/gen-db-json.py
already runs the same checks internally before it writes anything): the real
Downloader does **not** validate `linux`'s own sub-fields at all
(docs/downloader-contract.md §1, §10) -- a malformed publish surfaces only as
an uncaught traceback on every subscribed user's device. Running the check
again, standalone, against the file that is actually about to be uploaded to
GitHub Pages, is a second, independent gate in `.github/workflows/
publish-db.yml` -- the same "verify twice, trust once" pattern this repo uses
elsewhere (release.yml re-verifies the stock archive's hash AND its 7z
internal CRC; the shipped uboot.img is hashed before AND after the pinned-7za
round trip).

Usage:
    scripts/check-db-json-schema.py db.json --section mister_linux_modernization
    scripts/check-db-json-schema.py db.json --section mister_linux_modernization --require-linux

Exit: 0 = schema-valid, 1 = a contract violation (message on stderr),
      2 = usage/IO/JSON-parse error.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from db_entity_contract import DbSchemaError, validate  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("db_json", help="path to the db.json file to validate")
    ap.add_argument(
        "--section",
        required=True,
        help="downloader.ini section name / db_id this db is published under "
        "(docs/downloader-contract.md §1, §9.5)",
    )
    ap.add_argument(
        "--require-linux",
        action="store_true",
        help="fail if the db has no top-level 'linux' key at all",
    )
    args = ap.parse_args(argv)

    path = Path(args.db_json)
    try:
        text = path.read_text()
    except OSError as exc:
        print(f"error: cannot read {args.db_json}: {exc}", file=sys.stderr)
        return 2

    try:
        db_props = json.loads(text)
    except json.JSONDecodeError as exc:
        print(f"error: {args.db_json} is not valid JSON: {exc}", file=sys.stderr)
        return 2

    try:
        db_id, linux = validate(db_props, args.section)
    except DbSchemaError as exc:
        print(f"error: schema violation in {args.db_json}: {exc}", file=sys.stderr)
        return 1

    if args.require_linux and linux is None:
        print(
            f"error: {args.db_json} has no top-level 'linux' key "
            "(required by --require-linux)",
            file=sys.stderr,
        )
        return 1

    detail = f", linux.version={linux['version']!r}, linux.size={linux['size']}" if linux else ""
    print(f"OK: {args.db_json} is schema-valid (db_id={db_id!r}{detail})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
