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
        # utf-8-sig, not utf-8: a stray BOM would otherwise land inside the
        # first field name and turn a perfectly good manifest into the
        # "columns changed" error below, which points at the wrong problem.
        with open(path, newline="", encoding="utf-8-sig") as fh:
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


# A manifest.csv exercising every parsing decision this file makes, so the
# checks below are asserted against the real code path (load_manifest ->
# build_manifest_entry) rather than against the helpers in isolation:
#   busybox    -- ordinary row; depends on a package that is NOT in the file
#                 (host-pkgconf, via skeleton) and on two that are
#   skeleton   -- empty VERSION (versionless purl) and a host-* edge to drop
#   weird+pkg  -- '+' in the name and '/' in the version (both must encode),
#                 a LICENSE full of commas/parens, and a duplicated edge
#   toolchain  -- no dependencies at all
#   self-dep   -- names ITSELF as a dependency (must not self-loop)
SELF_TEST_CSV = """\
"PACKAGE","VERSION","LICENSE","LICENSE FILES","SOURCE ARCHIVE","SOURCE SITE","DEPENDENCIES WITH LICENSES"
"busybox","1.37.0","GPL-2.0","LICENSE","busybox-1.37.0.tar.bz2","https://busybox.net","skeleton [unknown] toolchain [unknown]"
"skeleton","","unknown","","","","host-pkgconf [GPL-2.0+]"
"weird+pkg","1.0/beta","MIT, BSD-3-Clause (foo, bar)","LICENSE","x.tar.gz","https://example.com","busybox [GPL-2.0] busybox [GPL-2.0]"
"toolchain","","unknown","","","",""
"self-dep","2.0","MIT","","","","self-dep [MIT] busybox [GPL-2.0]"
"""


def self_test():
    """Assert the conversion's parsing decisions. Returns 0 or 1.

    There is no pytest harness in this repo (see scripts/ci-tests.sh, which is
    a shell suite over BUILT artifacts and cannot reach a pure function), and
    every rule checked here is one a plausible "simplification" would silently
    break -- splitting the DEPENDENCIES column on whitespace, dropping the
    percent-encoding, treating every row as `direct`. `lint.yml` runs this.
    """
    import tempfile

    failures = []

    def check(label, got, want):
        if got != want:
            failures.append(f"{label}\n     got:  {got!r}\n     want: {want!r}")

    # Bracket-depth parsing: license text carries commas, parens and spaces,
    # so neither a whitespace nor a comma split can recover the names.
    check(
        "license text with commas/parens is not mistaken for package names",
        parse_dependency_names(
            "glibc [GPL-2.0+ (programs), LGPL-2.1+, BSD-3-Clause, MIT (library)] "
            "linux-headers [GPL-2.0]"
        ),
        ["glibc", "linux-headers"],
    )
    check("a bare (licenseless) name still parses", parse_dependency_names("foo"), ["foo"])
    check("an empty cell yields no names", parse_dependency_names(""), [])

    check("plain purl", purl_for("busybox", "1.37.0"), "pkg:generic/busybox@1.37.0")
    check(
        "empty version yields a versionless purl",
        purl_for("skeleton", ""),
        "pkg:generic/skeleton",
    )
    check(
        "'+' and '/' are percent-encoded in both segments",
        purl_for("weird+pkg", "1.0/beta"),
        "pkg:generic/weird%2Bpkg@1.0%2Fbeta",
    )

    with tempfile.TemporaryDirectory() as tmp:
        csv_path = Path(tmp) / "manifest.csv"
        csv_path.write_text(SELF_TEST_CSV, encoding="utf-8")
        entry = build_manifest_entry("t", str(csv_path))
        resolved = entry["resolved"]

        # Never index `resolved` directly: a regression in the purl scheme
        # changes every KEY, and a bare `resolved[...]` would then abort the
        # run with a KeyError traceback -- losing the checks after it AND the
        # already-recorded purl failure that explains the whole thing. Report
        # a missing key as a failed check like any other.
        def field(purl, *path):
            if purl not in resolved:
                return f"<no resolved entry keyed {purl}>"
            node = resolved[purl]
            for key in path:
                if not isinstance(node, dict) or key not in node:
                    return f"<{purl} has no {'.'.join(path)}>"
                node = node[key]
            return node

        check("every row becomes one resolved entry", len(resolved), 5)
        check(
            "resolved is keyed by each entry's own package_url",
            sorted(resolved),
            sorted(e["package_url"] for e in resolved.values()),
        )

        rel = {k: v["relationship"] for k, v in resolved.items()}
        check(
            "only packages nothing else depends on are direct",
            sorted(k for k, v in rel.items() if v == "direct"),
            ["pkg:generic/self-dep@2.0", "pkg:generic/weird%2Bpkg@1.0%2Fbeta"],
        )
        check(
            "a self-naming row does not become its own dependency",
            field("pkg:generic/self-dep@2.0", "dependencies"),
            ["pkg:generic/busybox@1.37.0"],
        )
        check(
            "a repeated edge is emitted once",
            field("pkg:generic/weird%2Bpkg@1.0%2Fbeta", "dependencies"),
            ["pkg:generic/busybox@1.37.0"],
        )
        check(
            "an edge naming a package absent from this manifest is dropped",
            field("pkg:generic/skeleton", "dependencies"),
            [],
        )
        check(
            "metadata carries the license verbatim, commas and all",
            field("pkg:generic/weird%2Bpkg@1.0%2Fbeta", "metadata", "license"),
            "MIT, BSD-3-Clause (foo, bar)",
        )
        check(
            "a row with no source site records no source_site key",
            "source_site" in resolved.get("pkg:generic/toolchain", {}).get("metadata", {}),
            False,
        )
        check(
            "every entry is runtime-scoped",
            {v["scope"] for v in resolved.values()},
            {"runtime"},
        )

        # A second run over the same input must be byte-identical: the graph
        # is submitted per release and a spurious diff is noise.
        check("output is deterministic", build_manifest_entry("t", str(csv_path)), entry)

        # The format guard has to fire on a changed header, not shrug at it.
        for label, body in (
            ("empty file", ""),
            ("wrong columns", '"PACKAGE","VERSION"\n"a","1"\n'),
            ("header but no rows", SELF_TEST_CSV.splitlines()[0] + "\n"),
        ):
            bad = Path(tmp) / "bad.csv"
            bad.write_text(body, encoding="utf-8")
            try:
                build_manifest_entry("bad", str(bad))
            except ManifestError:
                pass
            else:
                failures.append(f"{label} was accepted; expected ManifestError")

    if failures:
        for f in failures:
            print(f"::error::self-test: {f}", file=sys.stderr)
        print(f"self-test FAILED ({len(failures)} check(s))", file=sys.stderr)
        return 1
    print("self-test OK", file=sys.stderr)
    return 0


def main(argv=None):
    if argv is None:
        argv = sys.argv[1:]
    # Checked BEFORE argparse, deliberately: --self-test needs none of the
    # six required arguments below, and the alternative (making all six
    # conditionally required) means hand-rolling argparse's own "the
    # following arguments are required" errors for the normal path. Any
    # other argument passed alongside --self-test is ignored.
    if "--self-test" in argv:
        return self_test()

    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="run the built-in conversion checks and exit; ignores every other argument",
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
    raise SystemExit(main())
