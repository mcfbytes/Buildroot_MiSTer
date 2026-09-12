#!/usr/bin/env bash
# fetch-buildroot.sh -- download, hash-verify and unpack the pinned Buildroot.
#
# usage: scripts/fetch-buildroot.sh <version> <sha256> <dl-dir> <unpack-dir>
#        scripts/fetch-buildroot.sh --verify-only <version> <sha256> <dl-dir>
#        scripts/fetch-buildroot.sh --showsig <version>
#
# The wrapper Makefile's $(BR_STAMP) rule calls this. Buildroot is never
# vendored (TASKS.md standing rule 1); the tarball lands in <dl-dir>, is
# verified BEFORE unpacking against <sha256>, and is unpacked to <unpack-dir>.
# Idempotent: an unpacked tree of the same version is left alone with no
# network access.
#
# WHERE THE HASH COMES FROM. <sha256> must be transcribed from Buildroot's
# GPG-clearsigned release manifest, never from a downloaded tarball:
#     https://buildroot.org/downloads/buildroot-<version>.tar.gz.sign
# `--showsig <version>` prints it. scripts/hash-sync-buildroot.sh does the
# transcription on a Renovate bump. Do NOT "fix" a mismatch below by pasting
# the actual hash into the Makefile -- that blesses whatever bytes arrived.
set -euo pipefail

url_for() { echo "https://buildroot.org/downloads/buildroot-$1.tar.gz"; }

if [ "${1:-}" = "--showsig" ]; then
	[ $# -eq 2 ] || { echo "usage: $0 --showsig <version>" >&2; exit 2; }
	echo "==> $(url_for "$2").sign"
	exec curl -fsSL "$(url_for "$2").sign"
fi
verify_only=false
if [ "${1:-}" = "--verify-only" ]; then verify_only=true; shift; set -- "$@" /nonexistent; fi
[ $# -eq 4 ] || { echo "usage: $0 [--verify-only] <version> <sha256> <dl-dir> [<unpack-dir>]" >&2; exit 2; }
version=$1 sha256=$2 dl_dir=$3 br_dir=$4
tarball="$dl_dir/buildroot-$version.tar.gz"

for t in curl tar sha256sum; do
	command -v "$t" >/dev/null 2>&1 || { echo "FATAL: required tool '$t' not found in PATH" >&2; exit 1; }
done

if [ "$verify_only" = false ] && [ -f "$br_dir/Makefile" ] && grep -qx "export BR2_VERSION := $version" "$br_dir/Makefile"; then
	echo "==> Buildroot $version already present at $br_dir"
	exit 0
fi

mkdir -p "$dl_dir"
if [ ! -f "$tarball" ]; then
	echo "==> Downloading Buildroot $version"
	# .tmp then rename: an interrupted transfer never parks a truncated tarball at the real path.
	curl -fSL --retry 3 -o "$tarball.tmp" "$(url_for "$version")"
	mv "$tarball.tmp" "$tarball"
fi

echo "==> Verifying SHA-256 of $tarball"
if ! echo "$sha256  $tarball" | sha256sum -c - >/dev/null 2>&1; then
	cat >&2 <<MSG

FATAL: SHA-256 mismatch for $tarball
  expected: $sha256
  actual:   $(sha256sum "$tarball" | cut -d' ' -f1)

Refusing to unpack a Buildroot tarball that does not match the pinned hash.
The cached tarball is corrupt, truncated, or not what upstream published.
To recover: rm -f $tarball && make buildroot-unpack
A new hash is legitimate ONLY when transcribed from upstream's signed manifest:
    scripts/fetch-buildroot.sh --showsig $version
MSG
	exit 1
fi
echo "==> SHA-256 OK ($sha256)"
[ "$verify_only" = false ] || exit 0

echo "==> Unpacking Buildroot $version to $br_dir"
rm -rf "$br_dir"
mkdir -p "$br_dir"
tar -C "$br_dir" --strip-components=1 -xf "$tarball"
