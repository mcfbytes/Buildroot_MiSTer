#!/usr/bin/env bash
#
# hash-sync-font-noto-sans.sh — case 10 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml): refresh package/font-noto-sans/
# font-noto-sans.hash after a Renovate bump of FONT_NOTO_SANS_VERSION. Rationale
# in docs/ci.md#renovate-hash-sync-font-noto-sans.
#
# The source is a release ASSET (NotoSans-v<ver>.zip under a NotoSans-v<ver> tag
# of notofonts/latin-greek-cyrillic), not a $(call github,...) archive, so case 1's
# loop cannot build its URL. Same "locally computed" trust as case 1 and case 3:
# upstream publishes no checksums. OFL.txt is re-hashed from the same zip, with a
# ::warning:: if it changed.
#
# Records ONE row to $HASH_SYNC_OUTCOMES_FILE under the pin name "font-noto-sans":
# refreshed | already-current | skipped | failed. Appends, like every case script.
# Sets FONT_NOTO_SANS_HASH_CHANGED=0|1 via hash_sync_set_env. Exit 0 on every
# handled path.
#
# Usage: scripts/hash-sync-font-noto-sans.sh [REPO_ROOT]
# Required env: HASH_SYNC_OUTCOMES_FILE (see scripts/lib/hash-sync-common.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

PIN=font-noto-sans
ENV_VAR=FONT_NOTO_SANS_HASH_CHANGED

[ "$#" -le 1 ] || { echo "usage: $(basename "$0") [REPO_ROOT]" >&2; exit 2; }

REPO_ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
[ -d "$REPO_ROOT" ] || { echo "::error::REPO_ROOT '$REPO_ROOT' is not a directory" >&2; exit 2; }

: "${HASH_SYNC_OUTCOMES_FILE:?HASH_SYNC_OUTCOMES_FILE must be set}"

SCRATCH=""
# `return 0`: a non-zero EXIT trap status would fail the cheap already-current path.
cleanup() {
	if [ -n "$SCRATCH" ]; then
		rm -rf "$SCRATCH"
	fi
	return 0
}
trap cleanup EXIT

# done_with OUTCOME DETAIL CHANGED -- record the row, set the env var, finish.
done_with() {
	hash_sync_record "$outcomes_file" "$PIN" "$1" "$2"
	hash_sync_set_env "$ENV_VAR" "$3"
}

main() {
	cd "$REPO_ROOT"
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local mk="package/font-noto-sans/font-noto-sans.mk"
	local hashfile="package/font-noto-sans/font-noto-sans.hash"
	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping $PIN"
		done_with skipped "$mk or $hashfile not found in this checkout" 0
		return 0
	fi

	local version
	version=$(sed -n 's/^FONT_NOTO_SANS_VERSION[[:space:]]*=[[:space:]]*//p' "$mk" | head -1 | tr -d '[:space:]' || true)
	if ! [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
		echo "::error::could not parse FONT_NOTO_SANS_VERSION from $mk (got '${version:-<nothing>}')"
		done_with failed "could not parse FONT_NOTO_SANS_VERSION from $mk -- workflow regex bug, not a network issue; lint still fails closed on the stale hash" 0
		return 0
	fi
	local asset="NotoSans-v${version}.zip"

	local oldline
	oldline=$(awk '$1 == "sha256" && $3 ~ /\.zip$/ { print; exit }' "$hashfile" || true)
	if [ "${oldline##*  }" = "$asset" ]; then
		echo "$hashfile already pins $asset -- nothing to do."
		done_with already-current "already pins $asset" 0
		return 0
	fi

	SCRATCH="$(mktemp -d)"
	local url="https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v${version}/${asset}"
	local out="$SCRATCH/$asset"
	echo "==> fetching $url"
	if ! curl -fsSL --retry 3 "$url" -o "$out"; then
		echo "::warning::could not download $url -- leaving $hashfile untouched"
		done_with skipped "could not download $url" 0
		return 0
	fi
	local newhash
	newhash=$(sha256sum "$out" | cut -d' ' -f1)

	local license_hash
	if ! unzip -l "$out" OFL.txt >/dev/null 2>&1; then
		echo "::error::$asset has no OFL.txt at its root"
		done_with failed "OFL.txt missing from $asset -- FONT_NOTO_SANS_LICENSE_FILES needs a human before this pin can move" 0
		return 0
	fi
	license_hash=$(unzip -p "$out" OFL.txt | sha256sum | cut -d' ' -f1)
	local oldlic
	oldlic=$(awk '$1 == "sha256" && $3 == "OFL.txt" { print $2 }' "$hashfile" || true)
	if [ -n "$oldlic" ] && [ "$oldlic" != "$license_hash" ]; then
		echo "::warning::Noto Sans OFL.txt changed ($oldlic -> $license_hash) -- read the upstream diff before merging"
	fi

	# Rewrite the two lines in place by filename, so the header comment survives.
	local newline="sha256  ${newhash}  ${asset}"
	awk -v zipline="$newline" -v lic="sha256  ${license_hash}  OFL.txt" '
		$1 == "sha256" && $3 ~ /\.zip$/   { print zipline; next }
		$1 == "sha256" && $3 == "OFL.txt" { print lic; next }
		{ print }
	' "$hashfile" >"$hashfile.tmp"
	mv "$hashfile.tmp" "$hashfile"

	echo "Updated $hashfile:"
	echo "  old: $oldline"
	echo "  new: $newline"
	done_with refreshed "sha256 updated: $oldline -> $newline" 1
	return 0
}

main
