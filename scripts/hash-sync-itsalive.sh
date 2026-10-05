#!/usr/bin/env bash
#
# hash-sync-itsalive.sh — case 9 of the Renovate hash-sync workflow
# (.github/workflows/renovate-hash-sync.yml): refresh package/itsalive/itsalive.hash
# after a Renovate bump of ITSALIVE_VERSION. The cargo counterpart of case 7
# (scripts/hash-sync-azcopy.sh); rationale in docs/ci.md#renovate-hash-sync-itsalive.
#
# itsalive is a cargo-package, so the hashed file is the post-`cargo vendor`
# itsalive-<sha>-cargoN.tar.gz, which no URL serves. This script REBUILDS it with
# Buildroot's own support/download/cargo-post-process and the cargo from the
# rust-bin tarball the pinned Buildroot tree pins (verified against its
# rust-bin.hash), then hashes the result. It must never be folded into case 1's
# curl-and-hash loop, and never writes a hash it did not get that way.
#
# Records ONE row to $HASH_SYNC_OUTCOMES_FILE under the pin name "itsalive":
# refreshed | already-current | skipped | failed. Appends, like every case script.
# Sets ITSALIVE_HASH_CHANGED=0|1 via hash_sync_set_env. Exit 0 on every handled path.
#
# Usage: scripts/hash-sync-itsalive.sh [REPO_ROOT]
#   REPO_ROOT must be a real checkout of this tree (it runs `make buildroot-unpack`).
#   A verified dl/rust-bin/<tarball> in it is reused instead of downloaded.
# Required env: HASH_SYNC_OUTCOMES_FILE (see scripts/lib/hash-sync-common.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/hash-sync-common.sh
. "$SCRIPT_DIR/lib/hash-sync-common.sh"

PIN=itsalive
ENV_VAR=ITSALIVE_HASH_CHANGED
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

# done_with OUTCOME DETAIL CHANGED -- record the row, set the env var, finish.
done_with() {
	hash_sync_record "$outcomes_file" "$PIN" "$1" "$2"
	hash_sync_set_env "$ENV_VAR" "$3"
}

main() {
	cd "$REPO_ROOT"
	outcomes_file="$(hash_sync_resolve_outcomes_file "$HASH_SYNC_OUTCOMES_FILE")"

	local mk="package/itsalive/itsalive.mk"
	local hashfile="package/itsalive/itsalive.hash"
	if [ ! -f "$mk" ] || [ ! -f "$hashfile" ]; then
		echo "::warning::$mk or $hashfile not found in this checkout -- skipping itsalive"
		done_with skipped "$mk or $hashfile not found in this checkout" 0
		return 0
	fi

	local version
	version=$(sed -n 's/^ITSALIVE_VERSION[[:space:]]*=[[:space:]]*//p' "$mk" | head -1 | tr -d '[:space:]' || true)
	if ! [[ "$version" =~ ^[0-9a-f]{40}$ ]]; then
		echo "::error::could not parse a 40-hex ITSALIVE_VERSION from $mk (got '${version:-<nothing>}')"
		done_with failed "could not parse ITSALIVE_VERSION from $mk -- workflow regex bug, not a network issue; lint still fails closed on the stale hash" 0
		return 0
	fi
	local base_name="itsalive-${version}"

	# Cheap check first: this step runs on every pin's bump PR, not just itsalive's.
	local oldline
	oldline=$(awk '$1 == "sha256" && $3 ~ /-cargo[0-9]+\.tar\.gz$/ { print; exit }' "$hashfile" || true)
	local oldname="${oldline##*  }"
	if [ "${oldname%-cargo*}" = "$base_name" ]; then
		echo "$hashfile already pins $oldname -- nothing to do."
		done_with already-current "already pins $oldname" 0
		return 0
	fi

	SCRATCH="$(mktemp -d)"
	mkdir -p "$SCRATCH/home"

	echo "==> unpacking the pinned Buildroot tree (for support/download/cargo-post-process)"
	if ! make buildroot-unpack; then
		echo "::warning::make buildroot-unpack failed -- leaving $hashfile untouched"
		done_with skipped "make buildroot-unpack failed -- could not obtain the pinned Buildroot tree" 0
		return 0
	fi
	local br="$REPO_ROOT/work/buildroot"

	# The post-process format version (-cargoN) and the rust pin, both from that tree.
	local fmt rust_version
	fmt=$(sed -n 's/^BR_FMT_VERSION_cargo[[:space:]]*=[[:space:]]*//p' "$br/package/pkg-download.mk" | tr -d '[:space:]' || true)
	rust_version=$(sed -n 's/^RUST_BIN_VERSION[[:space:]]*=[[:space:]]*//p' "$br/package/rust-bin/rust-bin.mk" | tr -d '[:space:]' || true)
	if ! [[ "$fmt" =~ ^-cargo[0-9]+$ ]] || [ -z "$rust_version" ]; then
		echo "::error::could not parse BR_FMT_VERSION_cargo ('$fmt') or RUST_BIN_VERSION ('$rust_version') from $br"
		done_with failed "could not parse BR_FMT_VERSION_cargo or RUST_BIN_VERSION from the pinned Buildroot tree -- upstream renamed a variable" 0
		return 0
	fi
	local asset="${base_name}${fmt}.tar.gz"

	local rust_tarball="rust-${rust_version}-${RUST_HOST}.tar.xz"
	local rust_sha
	rust_sha=$(awk -v f="$rust_tarball" '$1 == "sha256" && $3 == f { print $2 }' "$br/package/rust-bin/rust-bin.hash" || true)
	if [ -z "$rust_sha" ]; then
		echo "::error::no sha256 for $rust_tarball in $br/package/rust-bin/rust-bin.hash"
		done_with failed "no sha256 for $rust_tarball in the pinned Buildroot tree's package/rust-bin/rust-bin.hash" 0
		return 0
	fi

	local rust_file="$SCRATCH/$rust_tarball"
	local cached="$REPO_ROOT/dl/rust-bin/$rust_tarball"
	if [ -f "$cached" ] && echo "${rust_sha}  $cached" | sha256sum -c - >/dev/null 2>&1; then
		echo "==> using the verified $cached"
		rust_file="$cached"
	else
		echo "==> fetching Rust $rust_version (pinned by the Buildroot tree, verified against its rust-bin.hash)"
		if ! curl -fsSL --retry 3 "https://static.rust-lang.org/dist/${rust_tarball}" -o "$rust_file"; then
			echo "::warning::could not download $rust_tarball -- leaving $hashfile untouched"
			done_with skipped "could not download $rust_tarball" 0
			return 0
		fi
		if ! echo "${rust_sha}  $rust_file" | sha256sum -c - >/dev/null; then
			echo "::error::$rust_tarball does not match the sha256 Buildroot pins for it"
			done_with failed "$rust_tarball sha256 mismatch against the pinned rust-bin.hash -- refusing to vendor with an unverified toolchain" 0
			return 0
		fi
	fi
	# Only the cargo component: `cargo vendor` never invokes rustc.
	tar -C "$SCRATCH" -xJf "$rust_file" "rust-${rust_version}-${RUST_HOST}/cargo"
	local cargo_bin="$SCRATCH/rust-${rust_version}-${RUST_HOST}/cargo/bin"

	# The URL Buildroot fetches: $(call github,...) plus the wget backend's "/<file>".
	local url="https://github.com/mcfbytes/ItsAlive_MiSTer/archive/${version}/${base_name}.tar.gz"
	local out="$SCRATCH/output"
	echo "==> fetching $url"
	if ! curl -fsSL --retry 3 "$url" -o "$out"; then
		echo "::warning::could not download $url -- leaving $hashfile untouched"
		done_with skipped "could not download $url" 0
		return 0
	fi

	# Buildroot's DL_ENV for a cargo-package, under `env -i`; cwd is a scratch dir
	# as dl-wrapper arranges. --locked inside cargo-post-process keeps Cargo.lock authoritative.
	local wd="$SCRATCH/vendor"
	mkdir -p "$wd"
	echo "==> vendoring with Buildroot's cargo-post-process (cargo $rust_version)"
	if ! (cd "$wd" && env -i \
		HOME="$SCRATCH/home" \
		PATH="$cargo_bin:/usr/local/bin:/usr/bin:/bin" \
		TAR=tar \
		CARGO_HOME="$SCRATCH/cargo-home" \
		"$br/support/download/cargo-post-process" -o "$out" -n "$base_name"); then
		echo "::warning::cargo vendor failed for itsalive $version -- leaving $hashfile untouched"
		done_with skipped "cargo-post-process failed (Cargo.lock out of date, or a crate fetch failed) -- read the step log" 0
		return 0
	fi

	local newhash
	newhash=$(sha256sum "$out" | cut -d' ' -f1)
	echo "==> $asset: $newhash ($(stat -c '%s' "$out") bytes)"

	# LICENSE, from the tarball just built: the download check never reads that line.
	local license_hash
	if ! license_hash=$(tar -xzOf "$out" "$base_name/LICENSE" 2>/dev/null | sha256sum | cut -d' ' -f1) ||
		! tar -tzf "$out" "$base_name/LICENSE" >/dev/null 2>&1; then
		echo "::error::itsalive $version's tarball has no LICENSE at its root"
		done_with failed "LICENSE missing from $base_name -- ITSALIVE_LICENSE_FILES needs a human before this pin can move" 0
		return 0
	fi
	local oldlic
	oldlic=$(awk '$1 == "sha256" && $3 == "LICENSE" { print $2 }' "$hashfile" || true)
	if [ -n "$oldlic" ] && [ "$oldlic" != "$license_hash" ]; then
		echo "::warning::itsalive's LICENSE changed ($oldlic -> $license_hash) -- read the upstream diff before merging"
	fi

	# Rewrite the two lines in place by filename, so the header comments survive.
	local newline="sha256  ${newhash}  ${asset}"
	awk -v tarline="$newline" -v lic="sha256  ${license_hash}  LICENSE" '
		$1 == "sha256" && $3 ~ /-cargo[0-9]+\.tar\.gz$/ { print tarline; next }
		$1 == "sha256" && $3 == "LICENSE"                { print lic; next }
		{ print }
	' "$hashfile" >"$hashfile.tmp"
	mv "$hashfile.tmp" "$hashfile"

	echo "Updated $hashfile:"
	echo "  old: $oldline"
	echo "  new: $newline"
	done_with refreshed "sha256 updated (rebuilt via cargo-post-process, cargo $rust_version): $oldline -> $newline" 1
	return 0
}

main
