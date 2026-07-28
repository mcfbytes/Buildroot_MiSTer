#!/usr/bin/env python3
"""sbom-to-dependency-snapshot.py -- Buildroot legal-info SBOM -> GitHub
dependency snapshot (TASKS.md P4.2's SBOM, surfaced in the dependency graph).

Every release already ships the SBOM as `legal-info.tar.gz`: Buildroot's
`manifest.csv`, one row per package actually built into the image, carrying
that package's exact version, license, and pinned upstream source URL. That
file is authoritative but it is a tarball asset -- nothing reads it but a
human who downloads it. This script re-expresses the same rows as a
"dependency snapshot" for GitHub's dependency submission API
(`POST /repos/{owner}/{repo}/dependency-graph/snapshots`), which is what
populates https://github.com/<owner>/<repo>/network/dependencies and, from
there, Dependabot alerts for anything the advisory database knows about.

Nothing here re-derives the package set: manifest.csv IS the input, so the
graph GitHub shows and the SBOM the release ships cannot disagree. If a
package is not in the shipped tarball it is not in the graph either.

## Usage

    scripts/sbom-to-dependency-snapshot.py \
        --manifest output/legal-info/manifest.csv \
        --manifest output-rt/legal-info/manifest.csv \
        --sha "$GITHUB_SHA" --ref refs/heads/master \
        --job-id "$GITHUB_RUN_ID" --job-correlator Release_dependency-graph \
        --job-html-url "$RUN_URL" --detector-url "$REPO_URL" \
        --out snapshot.json

A manifest's snapshot key defaults to the path it was read from; pass
`NAME=PATH` to name it explicitly.

Exit: 0 = snapshot written, 1 = a manifest was unusable (empty, wrong
header, no packages), 2 = usage/IO error.

## PURLs

Buildroot packages are not an "ecosystem" with a registry to name them in,
so every row becomes `pkg:generic/<name>@<version>` (name and version
percent-encoded per the purl spec). GitHub accepts arbitrary purl types --
since April 2025 the dependency graph preserves relationships for any
purl-identified package and files unknown types under the ecosystem "other"
-- so these render and stay linked rather than being dropped.

`pkg:generic` deliberately carries NO advisory-matching promise: GitHub can
only raise a Dependabot alert on a purl whose ecosystem it can look up. The
value here is the published inventory (what is in the image, at which
version, under which license), not alerting. Naming a package
`pkg:pypi/...`-style to buy matching would mean guessing an ecosystem
mapping for ~200 C packages, and a wrong guess is worse than no match: it
would assert a package identity the image does not actually ship. The
upstream source URL and license go in each entry's `metadata` so the row is
still traceable back to the manifest without a guess.

## direct vs indirect

Buildroot's manifest.csv has a DEPENDENCIES column ("<pkg> [<license>]
<pkg> [<license>] ..."), which is enough to reconstruct the DAG: a package
that appears in *some other* package's dependency list is `indirect`;
everything else is `direct`. That is a derivation, not a reading of the
Buildroot config -- a package can be both explicitly selected in the
defconfig and pulled in by another package, and this classifies it as
indirect. The distinction has no effect on what the graph lists; it only
shapes how GitHub draws the tree.

Dependency names that resolve to no row in the same manifest (host-*
build-time packages, virtual packages) are dropped from the edge list: a
purl pointing at a package the snapshot does not define would be a dangling
reference. The count of dropped edges is reported on stderr.
"""

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

# Bumped when the shape of what this emits changes (the purl scheme, the
# direct/indirect derivation, the metadata keys) -- NOT for a typo fix.
# GitHub keys "latest snapshot" on (job.correlator, detector.name), so this
# version is documentation for a human reading a snapshot, not a cache key.
DETECTOR_VERSION = "1.0.0"
DETECTOR_NAME = "buildroot-legal-info"

# Buildroot writes exactly this header row. Asserted, not assumed: a column
# reorder or rename upstream would otherwise silently produce a snapshot of
# empty versions rather than failing.
EXPECTED_COLUMNS = [
    "PACKAGE",
    "VERSION",
    "LICENSE",
    "LICENSE FILES",
    "SOURCE ARCHIVE",
    "SOURCE SITE",
    "DEPENDENCIES WITH LICENSES",
]


class ManifestError(Exception):
    """A manifest.csv that cannot be turned into a snapshot."""


def parse_dependency_names(cell):
    """Extract package names from a DEPENDENCIES WITH LICENSES cell.

    The cell is a space-separated run of `<name> [<license text>]` pairs, and
    the license text itself contains spaces, commas and parentheses --
    e.g. `glibc [GPL-2.0+ (programs), LGPL-2.1+, BSD-3-Clause, MIT (library)]
    linux-headers [GPL-2.0]`. So splitting on whitespace or commas is wrong;
    the only reliable structure is the brackets. Everything OUTSIDE a
    bracketed run is a package name.

    A package with no recorded license appears bare (no brackets), which this
    handles for free. Unbalanced brackets cannot happen in Buildroot output,
    but an unclosed one degrades to "the tail is licence text", not a crash.
    """
    depth = 0
    current = []
    for ch in cell:
        if ch == "[":
            depth += 1
        elif ch == "]":
            if depth > 0:
                depth -= 1
        elif depth == 0:
            current.append(ch)
    names = "".join(current).split()
    return names


def purl_for(name, version):
    """`pkg:generic/<name>@<version>`, percent-encoded per the purl spec.

    safe="" on both segments: a version like glibc's
    `2.43-45-gdae425b554207f7c4599c7fac707ad4c08545674` is already safe, but
    Buildroot versions can carry `/` (a branch-style VCS ref) or `+`, both of
    which change the purl's meaning if left literal. A row with an empty
    VERSION emits a versionless purl rather than a bare trailing `@`.
    """
    encoded_name = quote(name, safe="")
    if not version:
        return f"pkg:generic/{encoded_name}"
    return f"pkg:generic/{encoded_name}@{quote(version, safe='')}"


def load_manifest(path):
    """Read one Buildroot manifest.csv into {package name: row dict}."""
    try:
        with open(path, newline="", encoding="utf-8") as fh:
            reader = csv.DictReader(fh)
            if reader.fieldnames is None:
                raise ManifestError(f"{path}: file is empty (no header row)")
            if reader.fieldnames != EXPECTED_COLUMNS:
                raise ManifestError(
                    f"{path}: unexpected columns {reader.fieldnames!r}; "
                    f"expected {EXPECTED_COLUMNS!r} -- Buildroot's legal-info "
                    f"format changed and this converter needs updating"
                )
            rows = {}
            for row in reader:
                name = (row.get("PACKAGE") or "").strip()
                if not name:
                    continue
                rows[name] = row
    except OSError as exc:
        raise ManifestError(f"{path}: {exc}") from exc

    if not rows:
        raise ManifestError(
            f"{path}: header row present but no package rows -- refusing to "
            f"publish an empty dependency snapshot"
        )
    return rows


def build_manifest_entry(name, path):
    """Turn one manifest.csv into a snapshot `manifests` entry."""
    rows = load_manifest(path)

    # Pass 1: every package's purl, so pass 2's edges can point at rows that
    # exist. Two rows can collide on one purl only if Buildroot emitted the
    # same package twice; last write wins and the edge list is unaffected.
    purls = {pkg: purl_for(pkg, (row.get("VERSION") or "").strip()) for pkg, row in rows.items()}

    # Pass 2: edges + the direct/indirect derivation (see module docstring).
    edges = {}
    depended_on = set()
    dropped = 0
    for pkg, row in rows.items():
        deps = []
        for dep in parse_dependency_names(row.get("DEPENDENCIES WITH LICENSES") or ""):
            if dep == pkg:
                continue
            if dep not in purls:
                dropped += 1
                continue
            depended_on.add(dep)
            if purls[dep] not in deps:
                deps.append(purls[dep])
        edges[pkg] = deps

    resolved = {}
    for pkg, row in sorted(rows.items()):
        entry = {
            "package_url": purls[pkg],
            "relationship": "indirect" if pkg in depended_on else "direct",
            # Everything in manifest.csv is built INTO the shipped image --
            # legal-info's host-* build-time packages are a separate section
            # of the bundle and never appear as rows here. So "runtime" is
            # accurate for every row, and nothing maps to "development".
            "scope": "runtime",
            "dependencies": edges[pkg],
        }
        # The API caps metadata at 8 scalar keys; these three keep the row
        # traceable to its manifest line without re-reading the tarball.
        metadata = {}
        license_text = (row.get("LICENSE") or "").strip()
        source_site = (row.get("SOURCE SITE") or "").strip()
        source_archive = (row.get("SOURCE ARCHIVE") or "").strip()
        if license_text:
            metadata["license"] = license_text
        if source_site:
            metadata["source_site"] = source_site
        if source_archive:
            metadata["source_archive"] = source_archive
        if metadata:
            entry["metadata"] = metadata
        resolved[purls[pkg]] = entry

    if dropped:
        print(
            f"{path}: dropped {dropped} dependency edge(s) naming packages "
            f"absent from this manifest (host-* / virtual packages)",
            file=sys.stderr,
        )

    direct = sum(1 for e in resolved.values() if e["relationship"] == "direct")
    print(
        f"{path}: {len(resolved)} packages ({direct} direct, "
        f"{len(resolved) - direct} indirect) -> manifest '{name}'",
        file=sys.stderr,
    )

    # No `file.source_location`: the API documents it as a path relative to
    # the repository root, and manifest.csv is a build OUTPUT (output/ is
    # gitignored). Pointing at a path that does not exist in the tree would
    # render as a broken link in the graph UI.
    return {"name": name, "resolved": resolved}


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--manifest",
        action="append",
        required=True,
        metavar="[NAME=]PATH",
        help="a Buildroot legal-info manifest.csv; repeatable. NAME is the key "
        "it appears under in the snapshot (default: PATH).",
    )
    ap.add_argument("--sha", required=True, help="commit SHA the snapshot describes")
    ap.add_argument(
        "--ref",
        required=True,
        help="fully-qualified ref, e.g. refs/heads/master. GitHub only updates "
        "the repository's dependency results for a snapshot on the DEFAULT "
        "BRANCH -- a refs/tags/... ref is accepted and then ignored.",
    )
    ap.add_argument("--job-id", required=True, help="job identifier (e.g. $GITHUB_RUN_ID)")
    ap.add_argument(
        "--job-correlator",
        required=True,
        help="groups snapshots over time; GitHub keeps only the latest per "
        "(correlator, detector name), so this MUST be stable across releases",
    )
    ap.add_argument("--job-html-url", help="URL of the job that produced this snapshot")
    ap.add_argument("--detector-url", required=True, help="URL of this detector (the repo)")
    ap.add_argument(
        "--detector-name", default=DETECTOR_NAME, help=f"(default: {DETECTOR_NAME})"
    )
    ap.add_argument(
        "--detector-version", default=DETECTOR_VERSION, help=f"(default: {DETECTOR_VERSION})"
    )
    ap.add_argument(
        "--scanned",
        help="ISO-8601 UTC timestamp (default: now). Pass one for a reproducible run.",
    )
    ap.add_argument("--out", default="-", help="output path, or - for stdout (default: -)")
    ap.add_argument("--indent", type=int, default=2, help="JSON indent (default: 2)")
    args = ap.parse_args(argv)

    manifests = {}
    for spec in args.manifest:
        # Split on the FIRST '=' only: a bare path is the common case and a
        # path may itself contain '=' after the name separator.
        if "=" in spec:
            name, _, path = spec.partition("=")
            name = name.strip()
            if not name:
                print(f"::error::--manifest '{spec}' has an empty NAME", file=sys.stderr)
                return 2
        else:
            name, path = spec, spec
        if name in manifests:
            print(
                f"::error::--manifest name '{name}' given twice -- the second "
                f"would silently replace the first in the snapshot",
                file=sys.stderr,
            )
            return 2
        manifests[name] = path

    entries = {}
    failed = False
    for name, path in manifests.items():
        try:
            entries[name] = build_manifest_entry(name, path)
        except ManifestError as exc:
            print(f"::error::{exc}", file=sys.stderr)
            failed = True
    if failed:
        return 1

    scanned = args.scanned or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    job = {"id": args.job_id, "correlator": args.job_correlator}
    if args.job_html_url:
        job["html_url"] = args.job_html_url

    snapshot = {
        "version": 0,
        "sha": args.sha,
        "ref": args.ref,
        "job": job,
        "detector": {
            "name": args.detector_name,
            "version": args.detector_version,
            "url": args.detector_url,
        },
        "scanned": scanned,
        "manifests": entries,
    }

    text = json.dumps(snapshot, indent=args.indent, sort_keys=False) + "\n"
    if args.out == "-":
        sys.stdout.write(text)
    else:
        try:
            Path(args.out).write_text(text, encoding="utf-8")
        except OSError as exc:
            print(f"::error::cannot write {args.out}: {exc}", file=sys.stderr)
            return 2
        total = sum(len(m["resolved"]) for m in entries.values())
        print(
            f"wrote {args.out}: {len(entries)} manifest(s), {total} package(s)",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
