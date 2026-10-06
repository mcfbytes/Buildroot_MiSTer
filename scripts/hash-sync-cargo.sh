#!/usr/bin/env bash
#
# hash-sync-cargo.sh — case 9 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml): refresh the .hash of every
# cargo-vendored package after a Renovate bump of its *_VERSION. Table-driven
# over CARGO_PINS below (itsalive since 2026-10-04, slint since 2026-10-06; this
# file was scripts/hash-sync-itsalive.sh before slint joined). The cargo
# counterpart of case 7 (scripts/hash-sync-azcopy.sh); rationale in
# docs/ci.md#renovate-hash-sync-itsalive.
#
# Each hashed file is the post-`cargo vendor` <pkg>-<ver>-cargoN.tar.gz, which no
# URL serves. This script REBUILDS it with Buildroot's own
# support/download/cargo-post-process and the cargo from the rust-bin tarball the
# pinned Buildroot tree pins (verified against its rust-bin.hash), then hashes the
# result. It must never be folded into case 1's curl-and-hash loop, and never
# writes a hash it did not get that way. Every other sha256 line in the .hash
# (the licence files) is re-hashed from the same tarball.
#
# Records ONE row per pin to $HASH_SYNC_OUTCOMES_FILE, named after the package:
# refreshed | already-current | skipped | failed. Appends, like every case script.
# Sets CARGO_HASH_CHANGED=0|1 via hash_sync_set_env. Exit 0 on every handled path.
#
# Usage: scripts/hash-sync-cargo.sh [REPO_ROOT]
#   REPO_ROOT must be a real checkout of this tree (it runs `make buildroot-unpack`).
#   A verified dl/rust-bin/<tarball> in it is reused instead of downloaded.
# Required env: HASH_SYNC_OUTCOMES_FILE (see scripts/lib/hash-sync-common.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

# The cargo-vendored pins: package, then the GitHub archive URL Buildroot fetches
# ($(call github,...) plus the wget backend's "/<file>"), with @V@ for *_VERSION
# and @B@ for <pkg>-<ver>. A new cargo-package needs a line here and a regex below.
CARGO_PINS=(
	"itsalive https://github.com/mcfbytes/ItsAlive_MiSTer/archive/@V@/@B@.tar.gz"
	"slint https://github.com/slint-ui/slint/archive/v@V@/@B@.tar.gz"
)
ENV_VAR=CARGO_HASH_CHANGED
# The runner's triple; Buildroot's RUSTC_HOST_NAME on an x86_64 Linux host.
RUST_HOST=x86_64-unknown-linux-gnu

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

# version_ok PKG VERSION -- the shape each *_VERSION must have.
version_ok() {
	case "$1" in
	itsalive) [[ "$2" =~ ^[0-9a-f]{40}$ ]] ;;
	slint) [[ "$2" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ;;
	*) return 1 ;;
	esac
}

# Set by prepare_toolchain on first use, shared by every pin that needs a rebuild.
BR="" FMT="" RUST_VERSION="" CARGO_BIN="" TOOLCHAIN_ERR=""

# prepare_toolchain -- unpack the pinned Buildroot tree and its cargo, once.
# On failure sets TOOLCHAIN_ERR to "skipped|<reason>" or "failed|<reason>".
prepare_toolchain() {
	[ -z "$CARGO_BIN" ] && [ -z "$TOOLCHAIN_ERR" ] || return 0
	SCRATCH="$(mktemp -d)"
	mkdir -p "$SCRATCH/home"

	echo "==> unpacking the pinned Buildroot tree (for support/download/cargo-post-process)"
	if ! make buildroot-unpack; then
		echo "::warning::make buildroot-unpack failed -- leaving every cargo .hash untouched"
		TOOLCHAIN_ERR="skipped|make buildroot-unpack failed -- could not obtain the pinned Buildroot tree"
		return 0
	fi
	BR="$REPO_ROOT/work/buildroot"

	# The post-process format version (-cargoN) and the rust pin, both from that tree.
	FMT=$(sed -n 's/^BR_FMT_VERSION_cargo[[:space:]]*=[[:space:]]*//p' "$BR/package/pkg-download.mk" | tr -d '[:space:]' || true)
	RUST_VERSION=$(sed -n 's/^RUST_BIN_VERSION[[:space:]]*=[[:space:]]*//p' "$BR/package/rust-bin/rust-bin.mk" | tr -d '[:space:]' || true)
	if ! [[ "$FMT" =~ ^-cargo[0-9]+$ ]] || [ -z "$RUST_VERSION" ]; then
		echo "::error::could not parse BR_FMT_VERSION_cargo ('$FMT') or RUST_BIN_VERSION ('$RUST_VERSION') from $BR"
		TOOLCHAIN_ERR="failed|could not parse BR_FMT_VERSION_cargo or RUST_BIN_VERSION from the pinned Buildroot tree -- upstream renamed a variable"
		return 0
	fi

	local rust_tarball="rust-${RUST_VERSION}-${RUST_HOST}.tar.xz"
	local rust_sha
	rust_sha=$(awk -v f="$rust_tarball" '$1 == "sha256" && $3 == f { print $2 }' "$BR/package/rust-bin/rust-bin.hash" || true)
	if [ -z "$rust_sha" ]; then
		echo "::error::no sha256 for $rust_tarball in $BR/package/rust-bin/rust-bin.hash"
		TOOLCHAIN_ERR="failed|no sha256 for $rust_tarball in the pinned Buildroot tree's package/rust-bin/rust-bin.hash"
		return 0
	fi

	local rust_file="$SCRATCH/$rust_tarball"
	local cached="$REPO_ROOT/dl/rust-bin/$rust_tarball"
	if [ -f "$cached" ] && echo "${rust_sha}  $cached" | sha256sum -c - >/dev/null 2>&1; then
		echo "==> using the verified $cached"
		rust_file="$cached"
	else
		echo "==> fetching Rust $RUST_VERSION (pinned by the Buildroot tree, verified against its rust-bin.hash)"
		if ! curl -fsSL --retry 3 "https://static.rust-lang.org/dist/${rust_tarball}" -o "$rust_file"; then
			echo "::warning::could not download $rust_tarball -- leaving every cargo .hash untouched"
			TOOLCHAIN_ERR="skipped|could not download $rust_tarball"
			return 0
		fi
		if ! echo "${rust_sha}  $rust_file" | sha256sum -c - >/dev/null; then
			echo "::error::$rust_tarball does not match the sha256 Buildroot pins for it"
			TOOLCHAIN_ERR="failed|$rust_tarball sha256 mismatch against the pinned rust-bin.hash -- refusing to vendor with an unverified toolchain"
			return 0
		fi
	fi
	# Only the cargo component: `cargo vendor` never invokes rustc.
	tar -C "$SCRATCH" -xJf "$rust_file" "rust-${RUST_VERSION}-${RUST_HOST}/cargo"
	CARGO_BIN="$SCRATCH/rust-${RUST_VERSION}-${RUST_HOST}/cargo/bin"
}

# result OUTCOME DETAIL CHANGED -- what sync_pin hands back to main.
R_OUTCOME="" R_DETAIL="" R_CHANGED=0
result() {
	R_OUTCOME="$1" R_DETAIL="$2" R_CHANGED="$3"
}

# sync_pin PKG URL_TEMPLATE -- one pin, reported through result().
sync_pin() {
	local pkg="$1" url_tmpl="$2"
	local mk="package/$pkg/$pkg.mk" hashfile="package/$pkg/$pkg.hash"
	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping $pkg"
		result skipped "$mk or $hashfile not found in this checkout" 0
		return 0
	fi

	local var version
	var="$(echo "$pkg" | tr 'a-z-' 'A-Z_')_VERSION"
	version=$(sed -n "s/^${var}[[:space:]]*=[[:space:]]*//p" "$mk" | head -1 | tr -d '[:space:]' || true)
	if ! version_ok "$pkg" "$version"; then
		echo "::error::could not parse a well-formed $var from $mk (got '${version:-<nothing>}')"
		result failed "could not parse $var from $mk -- workflow regex bug, not a network issue; lint still fails closed on the stale hash" 0
		return 0
	fi
	local base_name="${pkg}-${version}"

	# Cheap check first: this step runs on every pin's bump PR, not just these.
	local oldline
	oldline=$(awk '$1 == "sha256" && $3 ~ /-cargo[0-9]+\.tar\.gz$/ { print; exit }' "$hashfile" || true)
	local oldname="${oldline##*  }"
	if [ "${oldname%-cargo*}" = "$base_name" ]; then
		echo "$hashfile already pins $oldname -- nothing to do."
		result already-current "already pins $oldname" 0
		return 0
	fi

	prepare_toolchain
	if [ -n "$TOOLCHAIN_ERR" ]; then
		result "${TOOLCHAIN_ERR%%|*}" "${TOOLCHAIN_ERR#*|}" 0
		return 0
	fi
	local asset="${base_name}${FMT}.tar.gz"

	local url="${url_tmpl//@V@/$version}"
	url="${url//@B@/$base_name}"
	local work="$SCRATCH/$pkg"
	mkdir -p "$work/vendor"
	local out="$work/output"
	echo "==> fetching $url"
	if ! curl -fsSL --retry 3 "$url" -o "$out"; then
		echo "::warning::could not download $url -- leaving $hashfile untouched"
		result skipped "could not download $url" 0
		return 0
	fi

	# Buildroot's DL_ENV for a cargo-package, under `env -i`; cwd is a scratch dir
	# as dl-wrapper arranges. --locked inside cargo-post-process keeps Cargo.lock authoritative.
	echo "==> vendoring $pkg with Buildroot's cargo-post-process (cargo $RUST_VERSION)"
	if ! (cd "$work/vendor" && env -i \
		HOME="$SCRATCH/home" \
		PATH="$CARGO_BIN:/usr/local/bin:/usr/bin:/bin" \
		TAR=tar \
		CARGO_HOME="$SCRATCH/cargo-home" \
		"$BR/support/download/cargo-post-process" -o "$out" -n "$base_name"); then
		echo "::warning::cargo vendor failed for $pkg $version -- leaving $hashfile untouched"
		result skipped "cargo-post-process failed (Cargo.lock out of date, or a crate fetch failed) -- read the step log" 0
		return 0
	fi

	local newhash
	newhash=$(sha256sum "$out" | cut -d' ' -f1)
	echo "==> $asset: $newhash ($(stat -c '%s' "$out") bytes)"

	# Every other sha256 line names a licence file: re-hash each from the tarball
	# just built (the download check never reads those lines).
	local newfile="$hashfile.tmp" f h old
	cp "$hashfile" "$newfile"
	while read -r f; do
		if ! tar -tzf "$out" "$base_name/$f" >/dev/null 2>&1; then
			rm -f "$newfile"
			echo "::error::$pkg $version's tarball has no $f"
			result failed "$f missing from $base_name -- the package's _LICENSE_FILES and .hash need a human before this pin can move" 0
			return 0
		fi
		h=$(tar -xzOf "$out" "$base_name/$f" | sha256sum | cut -d' ' -f1)
		old=$(awk -v f="$f" '$1 == "sha256" && $3 == f { print $2 }' "$hashfile")
		if [ "$old" != "$h" ]; then
			echo "::warning::$pkg's $f changed ($old -> $h) -- read the upstream diff before merging"
		fi
		awk -v f="$f" -v l="sha256  $h  $f" '$1 == "sha256" && $3 == f { print l; next } { print }' \
			"$newfile" >"$newfile.2"
		mv "$newfile.2" "$newfile"
	done < <(awk '$1 == "sha256" && $3 !~ /-cargo[0-9]+\.tar\.gz$/ { print $3 }' "$hashfile")

	# Rewrite the tarball line in place by filename, so the header comments survive.
	local newline="sha256  ${newhash}  ${asset}"
	awk -v tarline="$newline" '$1 == "sha256" && $3 ~ /-cargo[0-9]+\.tar\.gz$/ { print tarline; next } { print }' \
		"$newfile" >"$hashfile"
	rm -f "$newfile"

	echo "Updated $hashfile:"
	echo "  old: $oldline"
	echo "  new: $newline"
	result refreshed "sha256 updated (rebuilt via cargo-post-process, cargo $RUST_VERSION): $oldline -> $newline" 1
}

main() {
	cd "$REPO_ROOT"
	local outcomes_file changed=0 entry pkg
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"
	for entry in "${CARGO_PINS[@]}"; do
		pkg="${entry%% *}"
		result "" "" 0
		sync_pin "$pkg" "${entry#* }"
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
