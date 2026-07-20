#!/usr/bin/env bash
#
# verify-stock-payload.sh — the stock-archive verification chain extracted from
# .github/workflows/release.yml's `build` job, so it can be exercised on a
# laptop instead of only by pushing a `v*` tag.
#
# WHY THIS EXISTS. This chain is the MOST contract-critical code in the repo:
# it protects the on-device `Downloader_MiSTer` (`LinuxUpdater`), which fetches
# whatever `release_YYYYMMDD.7z` a published db.json names and feeds it
# straight to a PINNED, OLD, STATIC ARM `7za` binary already on the SD card
# (docs/downloader-contract.md §4-§8, §12). Nothing else in the pipeline
# catches a mistake here. Before this script existed, the ENTIRE chain lived
# inline in release.yml `run:` blocks and could only ever run by pushing a
# tag — a ~5 h build, on a real release. Now every subcommand below runs
# standalone, against a locally fetched archive, in seconds to minutes.
#
# THE PIN CONTRACT (read this before touching anything). Every STOCK_*
# environment variable this script reads is REQUIRED and is NEVER defaulted
# here — .github/workflows/release.yml's job-level `env:` block is the single
# source of truth for these values, and this script only ever reads them back.
# Do NOT hardcode a pin into this file, and do NOT give any of them a `:=`
# fallback (see scripts/fetch-sdcard-payload.sh for why that pattern is
# tempting and why it is deliberately NOT used here: this script must fail
# loudly, not silently drift, if release.yml's env block and this script's
# caller ever disagree). A local run therefore looks like:
#
#   export STOCK_RELEASE_URL=https://raw.githubusercontent.com/MiSTer-devel/SD-Installer-Win64_MiSTer/b8531c7848526d9a8227841923cc4a493cb6e631/release_20250402.7z
#   export STOCK_RELEASE_MD5=8dc3acae7d758a80a363fbd7ad31d95d
#   export STOCK_RELEASE_SHA256=5d087d9c501b2bc50aaf918146e7bf30e5981c08268d5a0e67a3233a4da642ba
#   export STOCK_RELEASE_SIZE=93727644
#   export STOCK_UBOOT_SHA256=e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64
#   export STOCK_UBOOT_SIZE=515141
#   export STOCK_UPDATEBOOT_SHA256=6ff2d50a080e26d7173b61c52083e9cc42ca658db0c5031b4da1c45c74a562f2
#   export STOCK_UPDATEBOOT_SIZE=407
#   export STOCK_7ZA_GZ_URL=https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/raw/master/7za.gz
#   export STOCK_7ZA_GZ_MD5=ed1ad5185fbede55cd7fd506b3c6c699
#   export STOCK_7ZA_GZ_SIZE=465600
#
# (copy these from release.yml's `build` job `env:` block, or better: `set -a;
# source <(yq -r '...')`-style extraction of that block, so a future pin bump
# there is automatically picked up here too — see that job's own header
# comment on why the pins live there and nowhere else.)
#
# ORDERING GUARANTEE (docs/downloader-contract.md §2, §5 — mirrors the real
# Downloader's own sequence, §2/§4). Full verification of the stock archive —
# size + MD5 + SHA-256, THEN a separate `7z t` internal-CRC test — MUST
# complete, successfully, before a single byte is extracted from it. This
# script enforces that ordering structurally: `verify-stock` performs both
# checks (in that order) and is the ONLY subcommand that may run before
# `extract-stock`; nothing in `extract-stock` re-derives or shortcuts that
# work. Callers (the workflow, or a human at a terminal) MUST invoke
# `verify-stock` and see it exit 0 before invoking `extract-stock` on the same
# archive. Across two separate process invocations this is machine-enforced,
# not merely a documented convention: `verify-stock` drops a
# `<archive>.verified` marker (the archive's own sha256) on success, and
# `extract-stock` refuses to run (exit 2) unless that marker exists and its
# recorded sha256 matches the archive's CURRENT sha256 — so a skipped or
# stale `verify-stock` is caught even when a caller (e.g. a human at a
# terminal, per the "runs standalone on a laptop" story above) invokes
# `extract-stock` directly.
#
# SUBCOMMANDS (each maps to one .github/workflows/release.yml step — the
# workflow keeps a same-named `- name:` step per subcommand below, calling
# straight into this script, so the run log stays exactly as readable as it
# was with the logic inline):
#
#   fetch-stock   <out-archive>
#       curl-fetch $STOCK_RELEASE_URL to <out-archive>. No verification —
#       that is `verify-stock`'s job, deliberately kept separate so a fetch
#       failure (network) and a verify failure (wrong bytes) never share one
#       error message.
#
#   verify-stock  <archive>
#       Full whole-archive verification, IN ORDER: size, then MD5, then
#       SHA-256, then (only once all three pass) `7z t` for the internal-CRC
#       test. Exits nonzero, with an ::error:: annotation, on the FIRST check
#       that fails — later checks do not run (matching a hash mismatch being
#       fatal, not retried, same as scripts/fetch-sdcard-payload.sh's stated
#       contract).
#
#   extract-stock <archive> <dest-dir>
#       `7z x -y <archive> files/linux/* -o<dest-dir>`. Exactly the pattern +
#       destination the real Downloader uses (docs/downloader-contract.md
#       §5) — only files/linux/* exists afterwards; the Windows-installer-
#       only members (files/MiSTer, files/menu.rbf,
#       files/MiSTer_example.ini, files/Scripts/, the .exe) are never
#       extracted and never shipped by us: they come from separate
#       MiSTer-devel projects, not from this Buildroot tree, and the
#       Downloader never reads them either. MUST only be called after
#       `verify-stock` has exited 0 for the same archive (see the ORDERING
#       GUARANTEE above) — machine-enforced via the `<archive>.verified`
#       marker `verify-stock` writes; refuses (exit 2) if it's missing or
#       stale.
#
#   verify-uboot  <extract-root> [--hash-only]
#       Re-verifies <extract-root>/files/linux/{uboot.img,updateboot}
#       (defense in depth, docs/downloader-contract.md §8/§12.1) against
#       $STOCK_UBOOT_SHA256/$STOCK_UBOOT_SIZE and
#       $STOCK_UPDATEBOOT_SHA256/$STOCK_UPDATEBOOT_SIZE. Used TWICE by the
#       workflow: once right after `extract-stock` (full size+sha256 check,
#       the default mode) and once after the pinned-7za round trip below
#       (`--hash-only`: sha256 only — a byte-identical round trip through a
#       correctly-functioning 7za cannot change size without also changing
#       the hash, so re-asserting size there would be pure redundancy, not a
#       stronger check; --hash-only reproduces that second workflow step's
#       assertions EXACTLY, no more and no less).
#
#   fetch-7za     <out-binary>
#       Fetches $STOCK_7ZA_GZ_URL to <out-binary>.gz, verifies its size + MD5
#       against $STOCK_7ZA_GZ_SIZE/$STOCK_7ZA_GZ_MD5, then `gunzip -k` +
#       `chmod +x` to produce <out-binary> — the EXACT static ARM `7za` the
#       real on-device Downloader fetches once and reuses forever
#       (docs/downloader-contract.md §4).
#
#   roundtrip     <our-archive> <7za-binary> <dest-dir>
#       Runs the pinned ARM `7za` from `fetch-7za`, under `qemu-arm`, against
#       an archive WE built: `7za t` (integrity — the Downloader's first
#       invocation) then `7za x -y ... files/linux/* -o<dest-dir>`
#       (extraction — the Downloader's second invocation, docs/downloader-
#       contract.md §5). Testing anything less specific than this literal
#       binary (e.g. a modern host `7z`) does not prove the compatibility
#       constraint (docs/downloader-contract.md §4). REQUIRES qemu-user
#       (`qemu-arm` on PATH) — see the guard note below.
#
#   verify-layout <our-archive> <release-stage-dir>
#       Cross-checks `7z l -slt <our-archive>`'s member list against
#       `find files -type f -o -type d` under <release-stage-dir> (the
#       assembled files/ tree the archive was created FROM), and separately
#       asserts a hand-maintained list of must-have members
#       (docs/reference-materials.md §2, docs/verification/
#       stock-release-20250402.md) so a silently-empty stock archive can't
#       vacuously pass the diff.
#
# qemu-user GUARD (`roundtrip` only). The pinned 7za is a static ARM binary;
# running it on an x86_64 host needs `qemu-arm` (qemu-user). CI always has it
# (the buildroot-build action installs it for the rest of the parity suite
# too); a bare laptop may not. `roundtrip` checks for `qemu-arm` on PATH
# before doing anything else and fails fast with an actionable message
# (install `qemu-user` / `qemu-user-static`) rather than a raw
# "command not found" — see the subcommand's own guard below.
#
# Usage: verify-stock-payload.sh <subcommand> [args...]
#        verify-stock-payload.sh --help
#
# Exit: 0 = the subcommand's check(s) passed. 1 = a check failed (an
#       ::error:: annotation is also emitted so it surfaces in the GitHub
#       Actions run UI, same as scripts/ci-tests.sh / scripts/check-abi.sh).
#       2 = usage error (bad/missing arguments, a required STOCK_* pin is
#       unset, or a required tool is missing from PATH).

set -euo pipefail

prog=${0##*/}

usage() {
	cat >&2 <<-EOF
	usage: $prog <subcommand> [args...]

	subcommands:
	  fetch-stock   <out-archive>
	  verify-stock  <archive>
	  extract-stock <archive> <dest-dir>
	  verify-uboot  <extract-root> [--hash-only]
	  fetch-7za     <out-binary>
	  roundtrip     <our-archive> <7za-binary> <dest-dir>
	  verify-layout <our-archive> <release-stage-dir>

	See this script's own header comment for the full contract (required
	STOCK_* environment variables, the verify-before-extract ordering
	guarantee, and the qemu-user requirement for 'roundtrip').
	EOF
}

# ---------------------------------------------------------------- helpers

# die MSG — emit an ::error:: annotation (so it surfaces in the GitHub
# Actions run UI, exactly as release.yml's inline steps did) and exit 1.
die() {
	printf '::error::%s\n' "$1" >&2
	exit 1
}

# usage_die MSG — bad invocation (missing arg, missing pin, missing tool):
# exit 2, no ::error:: annotation (this is a caller mistake, not a failed
# verification — same distinction ci-tests.sh/check-abi.sh draw between
# exit 1 and exit 2).
usage_die() {
	printf '%s: %s\n' "$prog" "$1" >&2
	usage
	exit 2
}

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || usage_die "required tool '$1' not found on PATH"
}

# require_env VAR... — every named variable must be a non-empty environment
# variable already. Never defaults, never assigns -- see this script's
# header on why a fallback here would defeat the whole point of extracting
# this chain (a silently-drifted pin would still "work").
require_env() {
	local var
	for var in "$@"; do
		if [ -z "${!var:-}" ]; then
			usage_die "required environment variable \$$var is not set -- release.yml's 'build' job env: block is the single source of truth for it; export it (see this script's header) before calling '$prog'"
		fi
	done
}

# ============================================================================
# fetch-stock <out-archive>
# ============================================================================
cmd_fetch_stock() {
	[ "$#" -eq 1 ] || usage_die "fetch-stock: expected exactly 1 argument (out-archive), got $#"
	local out=$1
	require_env STOCK_RELEASE_URL
	need_cmd curl

	curl -fL --retry 3 -o "$out" "$STOCK_RELEASE_URL"
	echo "fetch-stock: fetched $STOCK_RELEASE_URL -> $out"
}

# ============================================================================
# verify-stock <archive>
# ============================================================================
cmd_verify_stock() {
	[ "$#" -eq 1 ] || usage_die "verify-stock: expected exactly 1 argument (archive), got $#"
	local archive=$1
	require_env STOCK_RELEASE_SIZE STOCK_RELEASE_MD5 STOCK_RELEASE_SHA256
	need_cmd stat; need_cmd md5sum; need_cmd sha256sum; need_cmd 7z

	[ -f "$archive" ] || usage_die "verify-stock: '$archive' does not exist -- run 'fetch-stock' first"

	# 1. Size. Cheapest check first, same order as the original inline step.
	local actual_size
	actual_size=$(stat -c %s "$archive")
	if [ "$actual_size" != "$STOCK_RELEASE_SIZE" ]; then
		die "$archive size $actual_size != expected $STOCK_RELEASE_SIZE"
	fi

	# 2. MD5 -- what the real Downloader's db.json 'hash' field actually is
	# (docs/downloader-contract.md §2: MD5 of the whole .7z, streamed).
	local actual_md5
	actual_md5=$(md5sum "$archive" | cut -d' ' -f1)
	if [ "$actual_md5" != "$STOCK_RELEASE_MD5" ]; then
		die "$archive MD5 $actual_md5 != expected $STOCK_RELEASE_MD5"
	fi

	# 3. SHA-256 -- our own stronger, independent check on top of the MD5
	# the Downloader itself relies on.
	local actual_sha256
	actual_sha256=$(sha256sum "$archive" | cut -d' ' -f1)
	if [ "$actual_sha256" != "$STOCK_RELEASE_SHA256" ]; then
		die "$archive SHA-256 $actual_sha256 != expected $STOCK_RELEASE_SHA256"
	fi

	# 4. Second, INDEPENDENT check, only after all three whole-file checks
	# pass: 7z's own internal CRCs, same as the real Downloader's `7za t`
	# step (docs/downloader-contract.md §5). This ordering -- hash/size
	# checks fully complete, THEN a separate CRC test, THEN (by the caller,
	# never in this function) extraction -- is the ORDERING GUARANTEE this
	# script's header describes; do not reorder or merge these steps.
	local crc_log
	crc_log=$(mktemp)
	if ! 7z t "$archive" >"$crc_log" 2>&1; then
		printf '::error::%s\n' "7z t $archive failed (corrupt archive despite matching hash)" >&2
		cat "$crc_log" >&2
		rm -f "$crc_log"
		exit 1
	fi
	rm -f "$crc_log"

	# Machine-enforced verify-before-extract marker: 'extract-stock' refuses
	# to run unless this file exists and its sha256 matches the archive's
	# CURRENT sha256. In CI the linear step order already guarantees this,
	# but this script also "runs standalone on a laptop" (see header), where
	# nothing stops a caller from invoking 'extract-stock' directly and
	# skipping this function entirely -- this marker turns that documented
	# CALLER contract into something 'extract-stock' itself checks.
	printf '%s\n' "$actual_sha256" >"$archive.verified"

	echo "verify-stock: $archive verified -- size/MD5/SHA-256/internal-CRC all match."
}

# ============================================================================
# extract-stock <archive> <dest-dir>
# ============================================================================
cmd_extract_stock() {
	[ "$#" -eq 2 ] || usage_die "extract-stock: expected exactly 2 arguments (archive, dest-dir), got $#"
	local archive=$1 dest=$2
	need_cmd 7z; need_cmd sha256sum

	[ -f "$archive" ] || usage_die "extract-stock: '$archive' does not exist -- run 'fetch-stock'/'verify-stock' first"

	# Enforce the verify-before-extract ordering guarantee (see this
	# script's header and 'verify-stock''s marker comment above): refuse to
	# extract unless 'verify-stock' has already exited 0 for THIS exact
	# archive content, not merely this filename.
	local marker="$archive.verified"
	[ -f "$marker" ] || usage_die "extract-stock: '$archive' has not been verified -- run 'verify-stock' first"
	local archive_sha256
	archive_sha256=$(sha256sum "$archive" | cut -d' ' -f1)
	[ "$(cat "$marker")" = "$archive_sha256" ] || usage_die "extract-stock: '$archive' changed since it was verified -- run 'verify-stock' first"

	mkdir -p "$dest"
	# Exactly the pattern+destination the real Downloader uses
	# (docs/downloader-contract.md §5) -- only files/linux/* exists
	# afterwards; the Windows-installer-only members (files/MiSTer,
	# files/menu.rbf, files/MiSTer_example.ini, files/Scripts/, the .exe)
	# are never extracted and never shipped by us: they come from separate
	# MiSTer-devel projects, not from this Buildroot tree, and the
	# Downloader never reads them either.
	7z x -y "$archive" "files/linux/*" -o"$dest"
	echo "extract-stock: extracted files/linux/* from $archive -> $dest"
}

# ============================================================================
# verify-uboot <extract-root> [--hash-only]
# ============================================================================
cmd_verify_uboot() {
	[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage_die "verify-uboot: expected 1 or 2 arguments (extract-root [--hash-only]), got $#"
	local root=$1 hash_only=0
	if [ "$#" -eq 2 ]; then
		[ "$2" = "--hash-only" ] || usage_die "verify-uboot: unknown option '$2' (only --hash-only is accepted)"
		hash_only=1
	fi
	require_env STOCK_UBOOT_SHA256 STOCK_UPDATEBOOT_SHA256
	[ "$hash_only" -eq 1 ] || require_env STOCK_UBOOT_SIZE STOCK_UPDATEBOOT_SIZE
	need_cmd sha256sum
	[ "$hash_only" -eq 1 ] || need_cmd stat

	local uboot="$root/files/linux/uboot.img"
	local updateboot="$root/files/linux/updateboot"

	# Existence check runs in BOTH modes (not just full mode): under
	# `set -o pipefail`, a missing file here would otherwise make the
	# `sha256sum | cut` pipeline below fail via `set -e` with only a raw
	# `sha256sum: ...: No such file or directory` on stderr and no
	# `::error::` annotation -- silently losing the annotation the
	# original inline `run:` step (plain `set -eu`, no pipefail) emitted
	# on this path. --hash-only still only skips the *size* checks below,
	# never this existence guard.
	local f
	for f in "$uboot" "$updateboot"; do
		[ -f "$f" ] || die "missing $f after extraction"
	done

	local u_sha b_sha
	u_sha=$(sha256sum "$uboot" | cut -d' ' -f1)
	b_sha=$(sha256sum "$updateboot" | cut -d' ' -f1)

	if [ "$hash_only" -eq 0 ]; then
		local u_size b_size
		u_size=$(stat -c %s "$uboot")
		b_size=$(stat -c %s "$updateboot")
		[ "$u_size" = "$STOCK_UBOOT_SIZE" ] || die "uboot.img size $u_size != $STOCK_UBOOT_SIZE"
		[ "$u_sha" = "$STOCK_UBOOT_SHA256" ] || die "uboot.img sha256 $u_sha != $STOCK_UBOOT_SHA256 -- NOT byte-identical to stock, release-blocking (docs/downloader-contract.md §8/§12)"
		[ "$b_size" = "$STOCK_UPDATEBOOT_SIZE" ] || die "updateboot size $b_size != $STOCK_UPDATEBOOT_SIZE"
		[ "$b_sha" = "$STOCK_UPDATEBOOT_SHA256" ] || die "updateboot sha256 $b_sha != $STOCK_UPDATEBOOT_SHA256"
		echo "verify-uboot: uboot.img and updateboot confirmed byte-identical to stock."
	else
		[ "$u_sha" = "$STOCK_UBOOT_SHA256" ] || die "post-roundtrip uboot.img sha256 mismatch: $u_sha"
		[ "$b_sha" = "$STOCK_UPDATEBOOT_SHA256" ] || die "post-roundtrip updateboot sha256 mismatch: $b_sha"
		echo "verify-uboot: uboot.img/updateboot survive our archive's create+pinned-7za-extract round trip unchanged."
	fi
}

# ============================================================================
# fetch-7za <out-binary>
# ============================================================================
cmd_fetch_7za() {
	[ "$#" -eq 1 ] || usage_die "fetch-7za: expected exactly 1 argument (out-binary), got $#"
	local out=$1 gz="${1}.gz"
	require_env STOCK_7ZA_GZ_URL STOCK_7ZA_GZ_SIZE STOCK_7ZA_GZ_MD5
	need_cmd curl; need_cmd stat; need_cmd md5sum; need_cmd gunzip

	curl -fL --retry 3 -o "$gz" "$STOCK_7ZA_GZ_URL"
	local actual_size
	actual_size=$(stat -c %s "$gz")
	[ "$actual_size" = "$STOCK_7ZA_GZ_SIZE" ] || die "$gz size $actual_size != $STOCK_7ZA_GZ_SIZE"
	local actual_md5
	actual_md5=$(md5sum "$gz" | cut -d' ' -f1)
	[ "$actual_md5" = "$STOCK_7ZA_GZ_MD5" ] || die "$gz MD5 $actual_md5 != $STOCK_7ZA_GZ_MD5"

	# gunzip -k: keep $gz around (matches the original inline step), and
	# infers the output filename by stripping ".gz" off $gz -- which is
	# exactly $out, since $gz was constructed as "$out.gz" above.
	rm -f "$out"
	gunzip -k "$gz"
	chmod +x "$out"
	echo "fetch-7za: pinned ARM 7za fetched and verified -> $out"
}

# ============================================================================
# roundtrip <our-archive> <7za-binary> <dest-dir>
# ============================================================================
cmd_roundtrip() {
	[ "$#" -eq 3 ] || usage_die "roundtrip: expected exactly 3 arguments (our-archive, 7za-binary, dest-dir), got $#"
	local archive=$1 sevenza=$2 dest=$3

	# qemu-user GUARD: the pinned 7za is a static ARM binary; running it on
	# an x86_64 host needs qemu-arm. CI always has it (the buildroot-build
	# action installs it); a bare laptop may not -- fail fast with an
	# actionable message instead of a raw "command not found", per this
	# script's own header note on the guard.
	command -v qemu-arm >/dev/null 2>&1 || usage_die "'qemu-arm' not found on PATH -- the pinned ARM 7za is a static ARM binary and needs qemu-user to run on this host. Install qemu-user (Debian/Ubuntu: 'apt-get install qemu-user' or 'qemu-user-static') and retry; there is no host-native fallback, because proving byte-for-byte compatibility with the exact binary the real Downloader fetches is the entire point (docs/downloader-contract.md §4)."

	[ -f "$archive" ] || usage_die "roundtrip: '$archive' does not exist"
	[ -x "$sevenza" ] || usage_die "roundtrip: '$sevenza' does not exist or is not executable -- run 'fetch-7za' first"

	# 1. Integrity test -- exactly the Downloader's first 7za invocation.
	qemu-arm "$sevenza" t "$archive"
	# 2. Extraction -- exactly the Downloader's second invocation
	#    (docs/downloader-contract.md §5): files/linux/* only, into a
	#    fresh directory.
	mkdir -p "$dest"
	qemu-arm "$sevenza" x -y "$archive" "files/linux/*" -o"$dest"
	echo "roundtrip: pinned ARM 7za: both 't' and 'x -y ... files/linux/*' succeeded."
}

# ============================================================================
# verify-layout <our-archive> <release-stage-dir>
# ============================================================================
cmd_verify_layout() {
	[ "$#" -eq 2 ] || usage_die "verify-layout: expected exactly 2 arguments (our-archive, release-stage-dir), got $#"
	local archive=$1 stage=$2
	need_cmd 7z

	[ -f "$archive" ] || usage_die "verify-layout: '$archive' does not exist"
	[ -d "$stage/files" ] || usage_die "verify-layout: '$stage/files' does not exist -- expected the assembled release tree (release-stage/files)"

	local expected actual
	expected=$(cd "$stage" && find files -type f -o -type d | sort)
	# `7z l -slt` prints a "Path = " line for the ARCHIVE ITSELF in its
	# header block, before a "----------" separator and the per-member
	# list -- skip everything up to and including that separator, or the
	# archive's own filename corrupts this comparison as a phantom extra
	# member.
	actual=$(7z l -slt "$archive" | awk '/^----------$/{f=1; next} f' | sed -n 's/^Path = //p' | sort)
	if [ "$expected" != "$actual" ]; then
		printf '::error::%s\n' "archive member list does not match the assembled release tree" >&2
		echo "--- expected (from $stage/) ---" >&2
		echo "$expected" >&2
		echo "--- actual (from the .7z) ---" >&2
		echo "$actual" >&2
		exit 1
	fi

	# Explicit, human-readable cross-check against the documented canonical
	# set (docs/reference-materials.md §2, docs/verification/
	# stock-release-20250402.md) -- catches a silently-empty stock archive
	# passing the (vacuous) diff above.
	local must
	for must in files/linux/linux.img files/linux/zImage_dtb \
			files/linux/uboot.img files/linux/updateboot \
			files/linux/MidiLink.INI files/linux/ppp_options \
			files/linux/u-boot.txt_example files/linux/_samba.sh \
			files/linux/_user-startup.sh files/linux/_wpa_supplicant.conf; do
		echo "$actual" | grep -qx "$must" || die "archive is missing required member: $must"
	done
	echo "verify-layout: archive layout matches docs/downloader-contract.md / docs/reference-materials.md."
}

# ---------------------------------------------------------------- dispatch

[ "$#" -ge 1 ] || { usage; exit 2; }

case "$1" in
-h|--help|help)
	usage
	exit 0
	;;
esac

subcommand=$1
shift

case "$subcommand" in
fetch-stock)   cmd_fetch_stock "$@" ;;
verify-stock)  cmd_verify_stock "$@" ;;
extract-stock) cmd_extract_stock "$@" ;;
verify-uboot)  cmd_verify_uboot "$@" ;;
fetch-7za)     cmd_fetch_7za "$@" ;;
roundtrip)     cmd_roundtrip "$@" ;;
verify-layout) cmd_verify_layout "$@" ;;
*)
	usage_die "unknown subcommand '$subcommand'"
	;;
esac
