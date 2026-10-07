#!/usr/bin/env bash
#
# hash-sync-noto-fonts.sh — case 10 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml): refresh the .hash of each Noto font
# package after a Renovate bump of its *_VERSION. Table-driven over FONT_PINS below
# (font-noto-sans and font-noto-sans-jp, 2026-10-06). Rationale in
# docs/ci.md#renovate-hash-sync-font-noto-sans.
#
# Each source is a GitHub release ASSET, not a $(call github,...) archive, so case
# 1's loop cannot build its URL. Same "locally computed" trust as cases 1 and 3:
# upstream publishes no checksums. The licence file is re-hashed from the same zip,
# with a ::warning:: if it changed.
#
# An asset whose name carries no version (16_NotoSansJP.zip) is tracked by a
# "# hashed version: <ver>" line in its .hash, which this script rewrites too and
# lint.yml checks against the .mk.
#
# Records ONE row per pin to $HASH_SYNC_OUTCOMES_FILE, named after the package:
# refreshed | already-current | skipped | failed. Appends, like every case script.
# Sets NOTO_FONTS_HASH_CHANGED=0|1 via hash_sync_set_env. Exit 0 on every handled path.
#
# Usage: scripts/hash-sync-noto-fonts.sh [REPO_ROOT]
# Required env: HASH_SYNC_OUTCOMES_FILE (see scripts/lib/hash-sync-common.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

# package, asset name, release-download URL directory, licence file in the zip.
# @V@ is the package's *_VERSION. Mirrored by lint.yml's Noto pin-consistency step.
FONT_PINS=(
	"font-noto-sans NotoSans-v@V@.zip https://github.com/notofonts/latin-greek-cyrillic/releases/download/NotoSans-v@V@ OFL.txt"
	"font-noto-sans-jp 16_NotoSansJP.zip https://github.com/notofonts/noto-cjk/releases/download/Sans@V@ LICENSE"
)
ENV_VAR=NOTO_FONTS_HASH_CHANGED

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

# result OUTCOME DETAIL CHANGED -- what sync_pin hands back to main.
R_OUTCOME="" R_DETAIL="" R_CHANGED=0
result() {
	R_OUTCOME="$1" R_DETAIL="$2" R_CHANGED="$3"
}

# sync_pin PKG ASSET_TEMPLATE URL_DIR_TEMPLATE LICENCE -- one pin, via result().
sync_pin() {
	local pkg="$1" asset_tmpl="$2" dir_tmpl="$3" lic="$4"
	local mk="package/$pkg/$pkg.mk" hashfile="package/$pkg/$pkg.hash"
	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping $pkg"
		result skipped "$mk or $hashfile not found in this checkout" 0
		return 0
	fi

	local var version
	var="$(echo "$pkg" | tr 'a-z-' 'A-Z_')_VERSION"
	version=$(sed -n "s/^${var}[[:space:]]*=[[:space:]]*//p" "$mk" | head -1 | tr -d '[:space:]' || true)
	if ! [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
		echo "::error::could not parse a MAJOR.MINOR $var from $mk (got '${version:-<nothing>}')"
		result failed "could not parse $var from $mk -- workflow regex bug, not a network issue; lint still fails closed on the stale hash" 0
		return 0
	fi
	local asset="${asset_tmpl//@V@/$version}"
	local url="${dir_tmpl//@V@/$version}/$asset"
	# Versioned asset names identify the pin themselves; the others use the marker line.
	local marker=0
	[ "$asset_tmpl" = "${asset_tmpl//@V@/}" ] && marker=1

	local oldline oldver
	oldline=$(awk '$1 == "sha256" && $3 ~ /\.zip$/ { print; exit }' "$hashfile" || true)
	oldver=$(sed -n 's/^# hashed version:[[:space:]]*//p' "$hashfile" | tr -d '[:space:]')
	if { [ "$marker" = 0 ] && [ "${oldline##*  }" = "$asset" ]; } ||
		{ [ "$marker" = 1 ] && [ "${oldline##*  }" = "$asset" ] && [ "$oldver" = "$version" ]; }; then
		echo "$hashfile already pins $asset for $version -- nothing to do."
		result already-current "already pins $asset ($version)" 0
		return 0
	fi
	if [ "$marker" = 1 ] && [ -z "$oldver" ]; then
		echo "::error::$hashfile has no '# hashed version:' line"
		result failed "$hashfile lost its '# hashed version:' line -- restore it before this pin can move" 0
		return 0
	fi

	[ -n "$SCRATCH" ] || SCRATCH="$(mktemp -d)"
	local work="$SCRATCH/$pkg"
	mkdir -p "$work"
	local out="$work/$asset"
	echo "==> fetching $url"
	if ! curl -fsSL --retry 3 "$url" -o "$out"; then
		echo "::warning::could not download $url -- leaving $hashfile untouched"
		result skipped "could not download $url" 0
		return 0
	fi
	local newhash
	newhash=$(sha256sum "$out" | cut -d' ' -f1)

	if ! unzip -l "$out" "$lic" >/dev/null 2>&1; then
		echo "::error::$asset has no $lic at its root"
		result failed "$lic missing from $asset -- the package's _LICENSE_FILES needs a human before this pin can move" 0
		return 0
	fi
	local license_hash oldlic
	license_hash=$(unzip -p "$out" "$lic" | sha256sum | cut -d' ' -f1)
	oldlic=$(awk -v f="$lic" '$1 == "sha256" && $3 == f { print $2 }' "$hashfile" || true)
	if [ -n "$oldlic" ] && [ "$oldlic" != "$license_hash" ]; then
		echo "::warning::$pkg's $lic changed ($oldlic -> $license_hash) -- read the upstream diff before merging"
	fi

	# Rewrite the lines in place, so the header comments survive.
	local newline="sha256  ${newhash}  ${asset}"
	awk -v zipline="$newline" -v f="$lic" -v lic="sha256  ${license_hash}  $lic" -v ver="$version" '
		/^# hashed version:/               { print "# hashed version: " ver; next }
		$1 == "sha256" && $3 ~ /\.zip$/    { print zipline; next }
		$1 == "sha256" && $3 == f          { print lic; next }
		{ print }
	' "$hashfile" >"$hashfile.tmp"
	mv "$hashfile.tmp" "$hashfile"

	echo "Updated $hashfile:"
	echo "  old: $oldline${oldver:+ ($oldver)}"
	echo "  new: $newline ($version)"
	result refreshed "sha256 updated: $oldline${oldver:+ ($oldver)} -> $newline ($version)" 1
}

main() {
	cd "$REPO_ROOT"
	local outcomes_file changed=0 entry pkg asset dir lic
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"
	for entry in "${FONT_PINS[@]}"; do
		read -r pkg asset dir lic <<<"$entry"
		result "" "" 0
		sync_pin "$pkg" "$asset" "$dir" "$lic"
		if [ -z "$R_OUTCOME" ]; then
			result failed "sync_pin returned without an outcome -- a bug in this script" 0
		fi
		[ "$R_CHANGED" = 1 ] && changed=1
		hash_sync_record "$outcomes_file" "$pkg" "$R_OUTCOME" "$R_DETAIL"
	done
	hash_sync_set_env "$ENV_VAR" "$changed"
	return 0
}

main
