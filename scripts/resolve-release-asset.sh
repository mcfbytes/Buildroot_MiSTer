#!/usr/bin/env bash
#
# resolve-release-asset.sh — locate publish-db.yml's single release_YYYYMMDD.7z
# release asset and derive the db.json version from its FILENAME (P4.5,
# docs/db-json-versioning.md, ADR 0018).
#
# Extracted from publish-db.yml's "Locate the release_*.7z asset" step so the
# jq/sed can be exercised standalone against a saved release.json fixture, not
# only inline inside a workflow run.
#
# INPUT CONTRACT: a JSON file shaped like `gh release view <tag> --json
# isDraft,publishedAt,assets` (publish-db.yml's "Look up release metadata"
# step produces exactly this). This script does NOT re-check `isDraft` --
# publish-db.yml's own "Guard against a draft release" step already asserts
# that, as a separate, earlier gate, before this script ever runs (see that
# step's comment for why: the draft/published coupling with release.yml's
# deliberate draft-then-human-publish flow, P4.4). That guard is UNCHANGED and
# still lives in the workflow, not here -- this script only ever runs against
# an already-confirmed-published release.
#
# release.yml (P4.4) builds exactly one `release_YYYYMMDD.7z` asset per
# release. Fail loudly, not silently, on zero or multiple matches: either
# means a release built by something other than this project's own
# release.yml, or a naming regression in it.
#
# THE LOAD-BEARING VERSIONING RULE (ADR 0018, docs/db-json-versioning.md) --
# DO NOT "SIMPLIFY" THIS AWAY:
#
#   db.json's `linux.version` MUST equal the shipped image's /MiSTer.version,
#   BYTE FOR BYTE. The Downloader compares them by strict string inequality
#   (docs/downloader-contract.md §3): equal means "up to date, do nothing",
#   different means "re-flash". Both `/MiSTer.version` (baked in by
#   post-build.sh) and this release's archive filename trace to the SAME
#   source of truth -- the tagged commit's date that release.yml computed
#   MISTER_VERSION from and named the archive `release_YYYYMMDD.7z` with.
#
#   So the version emitted here is derived from the ARCHIVE FILENAME
#   (`archive_version`, the YYMMDD substring of release_YYYYMMDD.7z), and
#   DELIBERATELY NEVER from `publishedAt` (the moment a human clicked
#   "Publish release", which can differ from the build/commit date -- a
#   release drafted Monday and published Wednesday would mint the WRONG
#   version if publishedAt were used).
#
#   Get this wrong in either direction and every subscribed device
#   re-flashes on every Downloader run, forever: an image tagged/dated one
#   way with a db.json version computed a different way can never satisfy
#   the equality check, so it is never seen as "up to date". This is why the
#   rule survives here in the script that actually does the derivation, not
#   only in the ADR.
#
# Usage: scripts/resolve-release-asset.sh [release.json]
#   release.json defaults to "release.json" in the current directory (the
#   same relative path publish-db.yml's own steps read/write).
#
# Output: prints, to STDOUT, one `key=value` line per output key --
#     name=<asset filename>
#     url=<asset download URL>
#     size=<asset size in bytes>
#     published_at=<release publishedAt timestamp, passed through unchanged>
#     archive_version=<YYMMDD parsed from the filename -- see above>
#   -- always, so the script is directly usable standalone against a saved
#   fixture (pipe to `grep` / `cut`, or `source <(...)`-style consumption).
#   When $GITHUB_OUTPUT is set (i.e. running as a workflow step), the same
#   five lines are ALSO appended there, exactly as the original inline step
#   did. A one-line human-readable summary goes to STDERR so it never
#   pollutes the STDOUT key=value contract.
#
# Exit: 0 on success. 1 on a release-content problem (zero/multiple assets,
#   unparseable filename) -- each such failure is also emitted as a
#   GitHub Actions ::error:: annotation, exactly as the inline step did.
#   2 on a usage error (bad args, missing/unreadable input file).

set -euo pipefail

prog=${0##*/}

usage() {
	echo "usage: $prog [release.json]" >&2
	exit 2
}

[ "$#" -le 1 ] || usage

RELEASE_JSON="${1:-release.json}"
if [ ! -f "$RELEASE_JSON" ]; then
	echo "::error::release metadata file '$RELEASE_JSON' not found -- expected the output of: gh release view <tag> --json isDraft,publishedAt,assets" >&2
	exit 2
fi

count=$(jq '[.assets[] | select(.name | test("^release_[0-9]+\\.7z$"))] | length' "$RELEASE_JSON")
if [ "$count" -ne 1 ]; then
	echo "::error::expected exactly one release_<date>.7z asset, found $count" >&2
	echo "Assets present:" >&2
	jq -r '.assets[].name' "$RELEASE_JSON" >&2
	exit 1
fi

name=$(jq -r '.assets[] | select(.name | test("^release_[0-9]+\\.7z$")) | .name' "$RELEASE_JSON")
url=$(jq -r '.assets[] | select(.name | test("^release_[0-9]+\\.7z$")) | .url' "$RELEASE_JSON")
size=$(jq -r '.assets[] | select(.name | test("^release_[0-9]+\\.7z$")) | .size' "$RELEASE_JSON")
published_at=$(jq -r '.publishedAt' "$RELEASE_JSON")

# Stock's own db.json uses a 6-char YYMMDD version (verified: e.g. "250402"
# for release_20250402.7z), so strip the century -> db version = YYMMDD =
# /MiSTer.version, byte-for-byte, exactly matching stock's format. See the
# LOAD-BEARING VERSIONING RULE in this file's header for why this comes from
# the filename and never from publishedAt.
archive_version=$(printf '%s' "$name" | sed -n 's/^release_[0-9][0-9]\([0-9][0-9][0-9][0-9][0-9][0-9]\)\.7z$/\1/p')
if [ -z "$archive_version" ]; then
	echo "::error::could not parse YYMMDD from asset name '$name' (expected release_YYYYMMDD.7z)" >&2
	exit 1
fi

OUT=$(cat <<EOF
name=$name
url=$url
size=$size
published_at=$published_at
archive_version=$archive_version
EOF
)

printf '%s\n' "$OUT"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	printf '%s\n' "$OUT" >> "$GITHUB_OUTPUT"
fi

echo "Asset: $name ($size bytes), version=$archive_version (from filename); URL: $url" >&2
