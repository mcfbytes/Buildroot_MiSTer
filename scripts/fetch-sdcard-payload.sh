#!/usr/bin/env bash
#
# fetch-sdcard-payload.sh — fetch, verify, and stage every EXTERNAL payload
# item the full-SD-card installer image needs (docs/decisions/0017-...md §4,
# the 0020 amendment, TASKS.md P5.3, PLAN.md §8).
#
# This is a BUILD-TIME tool. It does not touch our own build outputs
# (output/images/linux.img, output/images/zImage_dtb, the installer
# zImage_dtb) — that overlay is scripts/mk-sdcard.sh's job, which runs this
# script first and then copies OUR artifacts on top, exactly mirroring how
# .github/workflows/release.yml's "Assemble release tree" step overlays its
# own fresh linux.img/zImage_dtb over an otherwise-stock files/linux/ tree.
#
# Sources staged, and why each is safe/necessary:
#
#   1. The pinned stock release_20250402.7z (SAME URL/MD5/SHA256/size as
#      .github/workflows/release.yml — do not let these drift independently;
#      if release.yml's STOCK_* values ever change, mirror the change here).
#      We verify it byte-for-byte BEFORE extracting anything from it, then
#      extract more members than release.yml does (which only takes
#      files/linux/*): files/linux/*, files/MiSTer, files/menu.rbf,
#      files/MiSTer_example.ini, files/Scripts/update.sh — the Windows-
#      installer-only members release.yml deliberately skips are exactly
#      what a from-scratch installer needs. uboot.img/updateboot are
#      re-verified by hash after extraction, same defense-in-depth
#      release.yml applies.
#   2. Scripts/update_all.sh — theypsilon/Update_All_MiSTer, raw file at a
#      pinned commit, sha256-verified (see PINNED_UPDATE_ALL_* below).
#   3. Scripts/wifi.sh — MiSTer-devel/Scripts_MiSTer, other_authors/wifi.sh,
#      raw file at a pinned commit, sha256-verified (see PINNED_WIFI_SH_*
#      below; path confirmed via docs/wifi-parity.md and the live repo).
#   4. _Console/*.rbf cores — MiSTer-devel/Distribution_MiSTer, ONLY when
#      SDCARD_CORES=1 (opt-in "full" variant). Not hash-pinned per the
#      accepted design (cores churn too fast for a stable per-file hash to
#      be worth maintaining) — instead pinned to a single source COMMIT
#      (PINNED_CORES_COMMIT below) for traceability, fetched via the GitHub
#      Contents API at that commit, and each file's size is cross-checked
#      against what that same API call reported (catches a truncated
#      download without requiring a content hash).
#
# Usage:
#   scripts/fetch-sdcard-payload.sh [STAGE_DIR]
#   STAGE_DIR=/some/dir scripts/fetch-sdcard-payload.sh
#   SDCARD_CORES=1 scripts/fetch-sdcard-payload.sh
#
# STAGE_DIR precedence: $1 wins over $STAGE_DIR wins over the default
# "<repo-root>/output-sdcard-stage" (mirrors the output-rt/output-initramfs
# naming the top-level Makefile already uses for per-stage build dirs).
#
# Result: <STAGE_DIR>/mister-payload/ populated per docs/verification/
# sdcard-payload.md's contract:
#   linux/...        (entire stock files/linux/*; mk-sdcard.sh overwrites
#                      linux/linux.img + linux/zImage_dtb with our own)
#   MiSTer            (stock files/MiSTer)
#   menu.rbf          (stock files/menu.rbf)
#   MiSTer.ini        (stock files/MiSTer_example.ini, renamed)
#   Scripts/update.sh, Scripts/update_all.sh, Scripts/wifi.sh
#   _Console/*.rbf    (only if SDCARD_CORES=1)
#
# Idempotent: safe to re-run. The large stock archive is downloaded once and
# cached under <STAGE_DIR>/.fetch-cache/ (skipped on a re-run if it is
# already present and still passes size+MD5+SHA-256); everything else is
# small enough that we simply re-fetch and re-verify every run, except
# already-downloaded core .rbf files (skipped if already present at the
# expected size).
#
# Exit: 0 = success. Non-zero + a message on stderr on any verification
# failure, missing tool, or network error (curl --retry covers transient
# blips; a hash/size mismatch is never retried — it means the wrong bytes
# arrived, not a flaky network).

set -o errexit
set -o nounset
set -o pipefail

# --- Locate the repo root -----------------------------------------------
# Assigned then marked readonly separately: `readonly X="$(cmd)"` masks
# cmd's exit status (shellcheck SC2155), matching the rest of scripts/.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# --- STAGE_DIR: $1 > $STAGE_DIR env > default ----------------------------
STAGE_DIR="${1:-${STAGE_DIR:-$REPO_ROOT/output-sdcard-stage}}"
readonly STAGE_DIR
readonly CACHE_DIR="$STAGE_DIR/.fetch-cache"
readonly WORK_DIR="$STAGE_DIR/.fetch-work"
readonly PAYLOAD_DIR="$STAGE_DIR/mister-payload"

# --- SDCARD_CORES: opt-in "full" variant ---------------------------------
SDCARD_CORES="${SDCARD_CORES:-0}"
readonly SDCARD_CORES

# --- Pinned stock reference archive --------------------------------------
# MUST match .github/workflows/release.yml's env block of the same names
# byte-for-byte. Overridable via environment so a caller (e.g. release.yml
# itself, once it wires this script in) can export its own copies instead
# of us duplicating the literals — but the defaults below are the source of
# truth if nothing overrides them.
: "${STOCK_RELEASE_URL:=https://raw.githubusercontent.com/MiSTer-devel/SD-Installer-Win64_MiSTer/b8531c7848526d9a8227841923cc4a493cb6e631/release_20250402.7z}"
: "${STOCK_RELEASE_MD5:=8dc3acae7d758a80a363fbd7ad31d95d}"
: "${STOCK_RELEASE_SHA256:=5d087d9c501b2bc50aaf918146e7bf30e5981c08268d5a0e67a3233a4da642ba}"
: "${STOCK_RELEASE_SIZE:=93727644}"
: "${STOCK_UBOOT_SHA256:=e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64}"
: "${STOCK_UBOOT_SIZE:=515141}"
: "${STOCK_UPDATEBOOT_SHA256:=6ff2d50a080e26d7173b61c52083e9cc42ca658db0c5031b4da1c45c74a562f2}"
: "${STOCK_UPDATEBOOT_SIZE:=407}"

# --- Pinned Scripts/update_all.sh ----------------------------------------
# theypsilon/Update_All_MiSTer, path "update_all.sh" (repo root). Pinned to
# a commit resolved from the repo's own commit history for that path
# (`git log -1 --format=%H -- update_all.sh` equivalent, via the GitHub API)
# on 2026-07-17. Bump by re-resolving the same way and re-recording the
# sha256 of the file at the new commit.
readonly PINNED_UPDATE_ALL_COMMIT="f15f5676474c342d6d0c8a86915c66971f3f5a44"
readonly PINNED_UPDATE_ALL_URL="https://raw.githubusercontent.com/theypsilon/Update_All_MiSTer/${PINNED_UPDATE_ALL_COMMIT}/update_all.sh"
readonly PINNED_UPDATE_ALL_SHA256="15db3c6050b5ee1960391344afe248ee49f25bdaae311051baeb7e77ab8c68f4"
readonly PINNED_UPDATE_ALL_SIZE="8628"

# --- Pinned Scripts/wifi.sh ------------------------------------------------
# MiSTer-devel/Scripts_MiSTer, path other_authors/wifi.sh (docs/wifi-parity.md
# confirms this exact path). Pinned to a commit resolved the same way as
# above on 2026-07-17.
readonly PINNED_WIFI_SH_COMMIT="1b5b6231a6bddf2266d99c405b11449ea35fb5b5"
readonly PINNED_WIFI_SH_URL="https://raw.githubusercontent.com/MiSTer-devel/Scripts_MiSTer/${PINNED_WIFI_SH_COMMIT}/other_authors/wifi.sh"
readonly PINNED_WIFI_SH_SHA256="10233fa31ea288f001a5e8cfba18e949270f79fed1295f7fc1d45e5fad78c988"
readonly PINNED_WIFI_SH_SIZE="5823"

# --- Pinned _Console cores source commit (SDCARD_CORES=1 only) -----------
# MiSTer-devel/Distribution_MiSTer HEAD as of 2026-07-17. Deliberately NOT
# per-file hash-pinned (user-waived caching for cores, per the accepted
# design in the plan this script implements) -- only the source commit is
# recorded, for traceability. Bump by re-resolving `git rev-parse HEAD`
# against that repo and re-running with the new value.
readonly PINNED_CORES_COMMIT="bb19b9f3d1a643ab707ad3d7fbb1b5c956ce300d"
readonly CORES_API_URL="https://api.github.com/repos/MiSTer-devel/Distribution_MiSTer/contents/_Console?ref=${PINNED_CORES_COMMIT}"

# --- small helpers ---------------------------------------------------------
log() { printf 'fetch-sdcard-payload: %s\n' "$*"; }
err() { printf 'fetch-sdcard-payload: ERROR: %s\n' "$*" >&2; }
die() { err "$*"; exit 1; }

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "required tool '$1' not found on PATH"
}

# size_of FILE -> stat -c %s, or empty string if the file does not exist.
size_of() {
	[ -f "$1" ] && stat -c %s "$1" || printf ''
}

# verify_file FILE EXPECTED_SIZE EXPECTED_SHA256 -> 0 if all match, else 1.
# Never fatal by itself -- callers decide whether a mismatch means
# "re-download" or "die".
verify_file() {
	local file="$1" want_size="$2" want_sha="$3"
	[ -f "$file" ] || return 1
	local got_size got_sha
	got_size="$(size_of "$file")"
	[ "$got_size" = "$want_size" ] || return 1
	got_sha="$(sha256sum "$file" | cut -d' ' -f1)"
	[ "$got_sha" = "$want_sha" ] || return 1
	return 0
}

# ============================================================================
# 1. Stock release archive: fetch (cached) + verify + extract needed members
# ============================================================================

fetch_verify_stock_archive() {
	local archive="$CACHE_DIR/stock_release.7z"
	mkdir -p "$CACHE_DIR"

	if [ -f "$archive" ]; then
		local size md5 sha
		size="$(size_of "$archive")"
		if [ "$size" = "$STOCK_RELEASE_SIZE" ]; then
			md5="$(md5sum "$archive" | cut -d' ' -f1)"
			sha="$(sha256sum "$archive" | cut -d' ' -f1)"
			if [ "$md5" = "$STOCK_RELEASE_MD5" ] && [ "$sha" = "$STOCK_RELEASE_SHA256" ]; then
				log "stock archive already cached and verified at $archive -- skipping download"
				return 0
			fi
		fi
		log "cached stock archive at $archive failed a check -- re-downloading"
		rm -f "$archive"
	fi

	log "downloading stock release archive from $STOCK_RELEASE_URL"
	curl -fL --retry 3 --retry-connrefused -o "$archive.partial" "$STOCK_RELEASE_URL"
	mv -f "$archive.partial" "$archive"

	local actual_size actual_md5 actual_sha256
	actual_size="$(stat -c %s "$archive")"
	[ "$actual_size" = "$STOCK_RELEASE_SIZE" ] ||
		die "stock_release.7z size $actual_size != expected $STOCK_RELEASE_SIZE"
	actual_md5="$(md5sum "$archive" | cut -d' ' -f1)"
	[ "$actual_md5" = "$STOCK_RELEASE_MD5" ] ||
		die "stock_release.7z MD5 $actual_md5 != expected $STOCK_RELEASE_MD5"
	actual_sha256="$(sha256sum "$archive" | cut -d' ' -f1)"
	[ "$actual_sha256" = "$STOCK_RELEASE_SHA256" ] ||
		die "stock_release.7z SHA-256 $actual_sha256 != expected $STOCK_RELEASE_SHA256"

	# Second, independent check: 7z's own internal CRCs (docs/downloader-
	# contract.md §5's own ordering; mirrors release.yml).
	if ! 7z t "$archive" >"$CACHE_DIR/stock-7z-test.log" 2>&1; then
		err "7z t $archive failed (corrupt archive despite matching hash)"
		cat "$CACHE_DIR/stock-7z-test.log" >&2
		die "aborting: stock archive failed internal-CRC test"
	fi
	log "stock archive verified: size/MD5/SHA-256/internal-CRC all match"
}

extract_stock_members() {
	local archive="$CACHE_DIR/stock_release.7z"
	local extract_dir="$WORK_DIR/stock-extract"
	rm -rf "$extract_dir"
	mkdir -p "$extract_dir"

	log "extracting needed members from stock archive"
	7z x -y "$archive" \
		"files/linux/*" \
		"files/MiSTer" \
		"files/menu.rbf" \
		"files/MiSTer_example.ini" \
		"files/Scripts/update.sh" \
		-o"$extract_dir" >/dev/null

	for member in \
		"files/linux/uboot.img" \
		"files/linux/updateboot" \
		"files/MiSTer" \
		"files/menu.rbf" \
		"files/MiSTer_example.ini" \
		"files/Scripts/update.sh"; do
		[ -f "$extract_dir/$member" ] || die "expected member '$member' missing after 7z extraction"
	done
}

reverify_uboot_updateboot() {
	local extract_dir="$WORK_DIR/stock-extract"
	local uboot="$extract_dir/files/linux/uboot.img"
	local updateboot="$extract_dir/files/linux/updateboot"

	verify_file "$uboot" "$STOCK_UBOOT_SIZE" "$STOCK_UBOOT_SHA256" ||
		die "uboot.img failed post-extraction size/sha256 verification -- NOT byte-identical to stock (docs/downloader-contract.md §8/§12)"
	verify_file "$updateboot" "$STOCK_UPDATEBOOT_SIZE" "$STOCK_UPDATEBOOT_SHA256" ||
		die "updateboot failed post-extraction size/sha256 verification"
	log "uboot.img and updateboot confirmed byte-identical to stock"
}

stage_stock_payload() {
	local extract_dir="$WORK_DIR/stock-extract/files"

	mkdir -p "$PAYLOAD_DIR/linux" "$PAYLOAD_DIR/Scripts"
	cp -a "$extract_dir/linux/." "$PAYLOAD_DIR/linux/"

	cp -f "$extract_dir/MiSTer" "$PAYLOAD_DIR/MiSTer"
	chmod 0755 "$PAYLOAD_DIR/MiSTer"

	cp -f "$extract_dir/menu.rbf" "$PAYLOAD_DIR/menu.rbf"
	cp -f "$extract_dir/MiSTer_example.ini" "$PAYLOAD_DIR/MiSTer.ini"
	cp -f "$extract_dir/Scripts/update.sh" "$PAYLOAD_DIR/Scripts/update.sh"
	chmod 0755 "$PAYLOAD_DIR/Scripts/update.sh"

	log "staged stock payload (linux/, MiSTer, menu.rbf, MiSTer.ini, Scripts/update.sh) into $PAYLOAD_DIR"
}

# ============================================================================
# 2. Scripts/update_all.sh and Scripts/wifi.sh — small, pinned raw fetches
# ============================================================================

fetch_pinned_script() {
	local url="$1" want_size="$2" want_sha="$3" dest="$4" label="$5"

	log "fetching $label"
	curl -fL --retry 3 --retry-connrefused -o "$dest.partial" "$url"
	mv -f "$dest.partial" "$dest"

	verify_file "$dest" "$want_size" "$want_sha" ||
		die "$label at $dest failed size/sha256 verification (expected size=$want_size sha256=$want_sha) -- pinned commit may have moved, or the fetch was tampered with"
	chmod 0755 "$dest"
	log "$label verified (sha256=$want_sha)"
}

fetch_update_all() {
	fetch_pinned_script \
		"$PINNED_UPDATE_ALL_URL" "$PINNED_UPDATE_ALL_SIZE" "$PINNED_UPDATE_ALL_SHA256" \
		"$PAYLOAD_DIR/Scripts/update_all.sh" \
		"Scripts/update_all.sh (theypsilon/Update_All_MiSTer@${PINNED_UPDATE_ALL_COMMIT})"
}

fetch_wifi_sh() {
	fetch_pinned_script \
		"$PINNED_WIFI_SH_URL" "$PINNED_WIFI_SH_SIZE" "$PINNED_WIFI_SH_SHA256" \
		"$PAYLOAD_DIR/Scripts/wifi.sh" \
		"Scripts/wifi.sh (MiSTer-devel/Scripts_MiSTer@${PINNED_WIFI_SH_COMMIT})"
}

# ============================================================================
# 3. _Console cores (SDCARD_CORES=1 only) -- no hash pin, commit-pin only
# ============================================================================

fetch_cores() {
	need_cmd jq

	local dest_dir="$PAYLOAD_DIR/_Console"
	mkdir -p "$dest_dir"

	log "listing _Console at MiSTer-devel/Distribution_MiSTer@${PINNED_CORES_COMMIT}"
	local listing="$WORK_DIR/console-listing.json"
	mkdir -p "$WORK_DIR"
	local -a auth_args=()
	if [ -n "${GITHUB_TOKEN:-}" ]; then
		auth_args=(-H "Authorization: Bearer $GITHUB_TOKEN")
	fi
	curl -fsSL --retry 3 --retry-connrefused \
		-H "Accept: application/vnd.github+json" \
		"${auth_args[@]}" \
		-o "$listing" \
		"$CORES_API_URL"

	# One jq pass builds a name<TAB>download_url<TAB>size manifest; the loop
	# below just reads it, instead of re-filtering the whole JSON document
	# on every iteration.
	local manifest="$WORK_DIR/console-manifest.tsv"
	jq -r '[.[] | select(.name | endswith(".rbf"))] | .[] | [.name, .download_url, (.size|tostring)] | @tsv' \
		"$listing" >"$manifest"

	local n
	n="$(wc -l <"$manifest")"
	[ "$n" -gt 0 ] || die "_Console listing at ${PINNED_CORES_COMMIT} returned zero .rbf files -- API shape changed or the pin is stale"
	log "found $n .rbf cores to fetch"

	local fetched=0 skipped=0 total_bytes=0
	local name url want_size got_size dest
	while IFS=$'\t' read -r name url want_size; do
		dest="$dest_dir/$name"
		got_size="$(size_of "$dest")"
		if [ "$got_size" = "$want_size" ]; then
			skipped=$((skipped + 1))
		else
			curl -fL --retry 3 --retry-connrefused -o "$dest.partial" "$url"
			mv -f "$dest.partial" "$dest"
			got_size="$(stat -c %s "$dest")"
			[ "$got_size" = "$want_size" ] ||
				die "core '$name' downloaded size $got_size != API-reported size $want_size (truncated/corrupt fetch)"
			fetched=$((fetched + 1))
		fi
		total_bytes=$((total_bytes + got_size))
	done <"$manifest"

	# Traceability record goes to WORK_DIR (build scratch), NOT inside
	# dest_dir: docs/verification/sdcard-payload.md §2 asserts every entry
	# under mister-payload/_Console/ matches "*.rbf" exactly, so nothing
	# else may be staged there.
	printf '%s\n' "$PINNED_CORES_COMMIT" >"$WORK_DIR/console-source-commit.txt"
	log "_Console: $fetched fetched, $skipped already present, $((total_bytes / 1024 / 1024)) MiB total (source commit ${PINNED_CORES_COMMIT}, recorded in $WORK_DIR/console-source-commit.txt)"
}

# ============================================================================
# main
# ============================================================================

main() {
	need_cmd curl
	need_cmd 7z
	need_cmd sha256sum
	need_cmd md5sum
	need_cmd stat

	mkdir -p "$STAGE_DIR" "$WORK_DIR" "$PAYLOAD_DIR"

	log "staging into $PAYLOAD_DIR (SDCARD_CORES=$SDCARD_CORES)"

	fetch_verify_stock_archive
	extract_stock_members
	reverify_uboot_updateboot
	stage_stock_payload

	fetch_update_all
	fetch_wifi_sh

	if [ "$SDCARD_CORES" = "1" ]; then
		fetch_cores
	else
		# Reconcile with the requested variant even on a re-run against a
		# STAGE_DIR a PRIOR SDCARD_CORES=1 invocation populated (e.g. a
		# release.yml job building both sdcard.img and sdcard-full.img back
		# to back off one cached stock archive) -- otherwise a stale
		# _Console/ tree from that earlier run would silently survive into
		# what is supposed to be the minimal variant, violating the
		# exact-inventory contract in docs/verification/sdcard-payload.md.
		rm -rf "$PAYLOAD_DIR/_Console"
		log "SDCARD_CORES != 1 -- skipping _Console cores (minimal variant)"
	fi

	log "done. Payload staged at $PAYLOAD_DIR"
}

main "$@"
