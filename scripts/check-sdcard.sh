#!/bin/sh
#
# check-sdcard.sh — static verification of a built `sdcard.img` (P5.3; ADR 0017 §4,
# amended by ADR 0020). No hardware, no boot -- everything here is asserted from the
# raw image file alone, the same posture as check-zimage-dtb.sh / check-linux-img.sh.
#
# Three independent assertions:
#
#  1. PARTITION TABLE CONTRACT. MBR partition 1 must be a FAT32 (`0x0c`) payload
#     partition and MBR partition 2 must be type `0xA2`, >= 1 MiB. This is *table
#     order*, not necessarily ascending on-disk order: U-Boot's `mmcload` reads
#     `mmc 0:$mmc_boot` with the compiled-in `mmc_boot=1` (boot-chain.md:172,309-310;
#     `docs/verification/stock-release-20250402.md`), i.e. it always wants MBR entry
#     *1*, and ADR 0017 §Decision-4 / ADR 0020 §2 both pin that entry to the FAT32
#     payload partition ("p1 = FAT32 data partition; p2 = type 0xA2", unchanged by
#     the 0020 amendment). `updateboot` independently confirms live boards carry the
#     `0xA2` partition as entry 2 (boot-chain.md:390-411, `/dev/mmcblk0p2`). Verified
#     via `sfdisk -d`, the same tool `updateboot`'s own "old vs new layout" probe
#     conceptually keys off.
#
#  2. THE 0xA2 PARTITION'S HEAD == the pinned `uboot.img`, byte-for-byte.
#     `updateboot` `dd`s the shipped `uboot.img` raw over this partition on every
#     Linux update (boot-chain.md:380-402) and the BootROM/SPL read the 4x64KiB SPL +
#     uImage from partition-relative offset 0 (boot-chain.md:74-137). A mismatched
#     head bricks the board on the very first update -- byte identity is the whole
#     contract (ADR 0017 §Decision-3, `docs/boot-chain.md` §3.2).
#
#  3. THE FAT32 PAYLOAD PARTITION'S FILE INVENTORY == docs/verification/sdcard-payload.md.
#     That doc's "## 1. Base inventory" fenced block is the exact (both-directions)
#     expected set: every promised path must be present, and nothing unlisted may be
#     present, EXCEPT the three directories §1.1 calls out as staged wholesale from the
#     stock archive (`gamecontrollerdb/`, `mt32-rom-data/`, `soundfonts/`, all under
#     `mister-payload/linux/`) -- those are asserted to exist and be non-empty, not
#     enumerated file-by-file (the archive-level `STOCK_RELEASE_SHA256` gate in
#     scripts/fetch-sdcard-payload.sh already covers their exact contents). When
#     $SDCARD_CORES=1, the doc's "## 2." addendum additionally requires
#     `mister-payload/_Console/` to exist, every entry directly inside it to match the glob
#     `*.rbf` (not hash-pinned -- ADR 0020 §3/§4), and the directory's total staged size to
#     stay under $EXPECT_CORES_MAX_BYTES (default ~600 MiB, ADR 0020 §3's "target ≲ 600 MiB
#     total payload" cap) -- measured via `mtools mcopy` (falling back to a root loop-mount)
#     and `du -sb`, independent of the mtools/loop-mount path used for the file inventory.
#
#     The doc's own convention (its "Directories are listed with a trailing /" line)
#     is the same convention `mtools mdir -b -/` emits, which is exactly why this
#     script can diff one against the other with no reformatting step.
#
# Usage:
#   scripts/check-sdcard.sh <sdcard.img> [uboot-ref] [payload-inventory.md]
#
#   <sdcard.img>            required. The raw (NOT .xz'd) hdimage produced by
#                           scripts/mk-sdcard.sh / board/mister/de10nano/genimage-sdcard.cfg.
#   [uboot-ref]             optional. Either a path to a reference uboot.img (byte-for-byte
#                           `cmp` against partition 2's head) or a 64-hex-char sha256 (hash
#                           compare instead). Falls back to $UBOOT_IMG (path), then
#                           $UBOOT_SHA256 (hash), then the pinned stock default below --
#                           the same STOCK_UBOOT_SHA256/STOCK_UBOOT_SIZE
#                           .github/workflows/release.yml and scripts/fetch-sdcard-payload.sh
#                           already use (ADR 0017 §Decision-3/5's default channel).
#   [payload-inventory.md]  optional. Default: docs/verification/sdcard-payload.md next to
#                           this script's repo root. Override with $PAYLOAD_INVENTORY.
#
#   $SDCARD_CORES            optional, default "0". "1" additionally requires and checks
#                           the doc's "## 2." `_Console` addendum (mirrors
#                           scripts/fetch-sdcard-payload.sh's own env var of the same name).
#
# Reading the FAT32 partition: prefers `mtools` (`mdir`, no privilege needed -- reads the
# raw image directly at a byte offset via mtools' `image@@offset` syntax; this is also
# genimage's/mk-sdcard.sh's own documented host dependency, so any runner that can build
# sdcard.img can also check it). Falls back to a real loop-mount (needs root) if `mdir` is
# not on PATH. The $SDCARD_CORES=1 size cap uses the same two-tier fallback via `mcopy`
# (also part of mtools) + `du -sb`, checked independently of the `mdir` inventory read.
#
# The 0xA2 partition's SIZE is pinned exactly: board/mister/de10nano/genimage-sdcard.cfg
# gives it `size = 4M` (8192 sectors), so $EXPECT_UBOOT_SIZE_SECTORS defaults to 8192 below
# (override if that file's `size =` ever changes -- keep the two in sync). Its START offset
# is deliberately NOT pinned: genimage places it immediately after partition 1, whose size
# is whatever mk-sdcard.sh's staged FAT32 payload turns out to be -- there is no fixed byte
# offset to assert. $EXPECT_UBOOT_START_SECTOR stays unset (informational-only) unless a
# caller has a specific build's known payload size to check against.
#
# Exit: 0 = all assertions pass; 1 = a contract violation; 2 = usage/IO/tooling error.

set -eu

prog=${0##*/}
fail=0

# --- pinned partition-table contract (ADR 0017 §Decision-4, ADR 0020 §2/§4) -----------
DATA_PART_NUM=1
UBOOT_PART_NUM=2
DATA_PART_TYPE=c            # 0x0c, FAT32 LBA -- board/mister/de10nano/genimage-sdcard.cfg
UBOOT_PART_TYPE=a2
MIN_UBOOT_PART_SECTORS=2048 # >= 1 MiB floor, TASKS.md P5.3 / boot-chain.md §2.1

# --- pinned stock uboot.img reference (MUST track release.yml's / fetch-sdcard-payload.sh's
# STOCK_UBOOT_SHA256 / STOCK_UBOOT_SIZE byte-for-byte -- there is no single source of truth
# to derive these from at check time, same caveat as check-linux-img.sh's header) -----------
: "${STOCK_UBOOT_SHA256:=e2d46cf9fe1ec40ca2c9c7409870249f267e06f70e5736dc6d30b4e21fe62a64}"
: "${STOCK_UBOOT_SIZE:=515141}"

# --- opaque "staged wholesale, existence+non-empty only" directories (sdcard-payload.md §1.1) --
OPAQUE_DIRS='mister-payload/linux/gamecontrollerdb/
mister-payload/linux/mt32-rom-data/
mister-payload/linux/soundfonts/'

CORES_DIR='mister-payload/_Console/'

: "${SDCARD_CORES:=0}"
: "${PAYLOAD_INVENTORY:=}"
: "${UBOOT_IMG:=}"
: "${UBOOT_SHA256:=}"
: "${EXPECT_UBOOT_START_SECTOR:=}"
# 4 MiB, board/mister/de10nano/genimage-sdcard.cfg's `size = 4M` for the uboot partition.
: "${EXPECT_UBOOT_SIZE_SECTORS:=8192}"
# ~600 MiB, sdcard-payload.md §2 / ADR 0020 §3's "target ≲ 600 MiB total payload" cap on the
# baked _Console set -- kept theoretical by this build-time gate, not relied on as the
# installer's only defense (that's the on-device free-RAM safety valve, ADR 0020 §3).
: "${EXPECT_CORES_MAX_BYTES:=629145600}"

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }

usage() {
	echo "usage: $prog <sdcard.img> [uboot-ref] [payload-inventory.md]" >&2
	exit 2
}

[ $# -ge 1 ] && [ $# -le 3 ] || usage
img=$1
uboot_ref=${2:-}
inventory_arg=${3:-}

[ -f "$img" ] || { echo "$prog: no such file: $img" >&2; exit 2; }

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

inventory_doc=${inventory_arg:-${PAYLOAD_INVENTORY:-}}
[ -n "$inventory_doc" ] || inventory_doc="$repo_root/docs/verification/sdcard-payload.md"
[ -f "$inventory_doc" ] || { echo "$prog: payload inventory doc not found: $inventory_doc" >&2; exit 2; }

command -v sfdisk >/dev/null 2>&1 || { echo "$prog: sfdisk (util-linux) not found on PATH" >&2; exit 2; }
command -v dd >/dev/null 2>&1 || { echo "$prog: dd not found on PATH" >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "$prog: sha256sum not found on PATH" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/check-sdcard.XXXXXX")
loopdev=""
mnt=""
# shellcheck disable=SC2329 # invoked indirectly via `trap cleanup EXIT` below
cleanup() {
	[ -n "$mnt" ] && umount "$mnt" >/dev/null 2>&1 || true
	[ -n "$loopdev" ] && losetup -d "$loopdev" >/dev/null 2>&1 || true
	rm -rf "$work"
}
trap cleanup EXIT

printf '%s: %s\n' "$prog" "$img"
printf '%s\n' "SDCARD_CORES=$SDCARD_CORES"

# =============================================================================
# 1. Partition table contract (sfdisk -d, MBR entry order -- see header note)
# =============================================================================

dump=$(sfdisk -d "$img" 2>/dev/null) || { echo "$prog: sfdisk -d failed on $img (not a partitioned image?)" >&2; exit 2; }

# One "<name>N : start=..., size=..., type=..." line per MBR slot, IN partition-table
# order -- so the Nth matching line is unambiguously MBR partition N, regardless of how
# sfdisk names the device from our (possibly odd) image path.
part_lines=$(printf '%s\n' "$dump" | grep -E '^[^[:space:]]+[0-9]+[[:space:]]*:.*start=') || true
part_count=$(printf '%s\n' "$part_lines" | grep -c . || true)
note "sfdisk -d reports $part_count partition(s)"

field() {  # field LINE NAME -> value (comma- or EOL-terminated; tolerates sfdisk's padding)
	printf '%s\n' "$1" | sed -n "s/.*[[:space:]]$2=[[:space:]]*\\([^,[:space:]]*\\).*/\\1/p"
}

get_part() {  # get_part N -> the Nth partition-table line, or empty
	printf '%s\n' "$part_lines" | sed -n "${1}p"
}

data_line=$(get_part "$DATA_PART_NUM")
uboot_line=$(get_part "$UBOOT_PART_NUM")

data_start=""
if [ -z "$data_line" ]; then
	bad "MBR partition $DATA_PART_NUM (FAT32 payload) not found ($part_count partition(s) in table)"
else
	data_start=$(field "$data_line" start)
	data_size=$(field "$data_line" size)
	data_type=$(field "$data_line" type)
	note "partition $DATA_PART_NUM: start=$data_start size=$data_size(sectors) type=$data_type"
	if [ "$data_type" = "$DATA_PART_TYPE" ]; then
		ok "partition $DATA_PART_NUM type=0x$DATA_PART_TYPE (FAT32) -- this is the partition U-Boot's mmc_boot=1 reads"
	else
		bad "partition $DATA_PART_NUM type='$data_type', expected '$DATA_PART_TYPE' (0x0c FAT32)"
	fi
fi

uboot_start=""
uboot_size=""
if [ -z "$uboot_line" ]; then
	bad "MBR partition $UBOOT_PART_NUM (0xA2) not found ($part_count partition(s) in table)"
else
	uboot_start=$(field "$uboot_line" start)
	uboot_size=$(field "$uboot_line" size)
	uboot_type=$(field "$uboot_line" type)
	note "partition $UBOOT_PART_NUM: start=$uboot_start size=$uboot_size(sectors) type=$uboot_type"
	if [ "$uboot_type" = "$UBOOT_PART_TYPE" ]; then
		ok "partition $UBOOT_PART_NUM type=0x$UBOOT_PART_TYPE (BootROM/SPL raw-partition contract, boot-chain.md §2.1)"
	else
		bad "partition $UBOOT_PART_NUM type='$uboot_type', expected '$UBOOT_PART_TYPE'"
	fi
	if [ "$uboot_size" -ge "$MIN_UBOOT_PART_SECTORS" ]; then
		ok "partition $UBOOT_PART_NUM size $uboot_size sectors >= $MIN_UBOOT_PART_SECTORS (1 MiB floor)"
	else
		bad "partition $UBOOT_PART_NUM size $uboot_size sectors < $MIN_UBOOT_PART_SECTORS (1 MiB floor)"
	fi
	if [ -n "$EXPECT_UBOOT_START_SECTOR" ]; then
		if [ "$uboot_start" = "$EXPECT_UBOOT_START_SECTOR" ]; then
			ok "partition $UBOOT_PART_NUM start == \$EXPECT_UBOOT_START_SECTOR ($EXPECT_UBOOT_START_SECTOR)"
		else
			bad "partition $UBOOT_PART_NUM start=$uboot_start != \$EXPECT_UBOOT_START_SECTOR=$EXPECT_UBOOT_START_SECTOR"
		fi
	fi
	if [ -n "$EXPECT_UBOOT_SIZE_SECTORS" ]; then
		if [ "$uboot_size" = "$EXPECT_UBOOT_SIZE_SECTORS" ]; then
			ok "partition $UBOOT_PART_NUM size == \$EXPECT_UBOOT_SIZE_SECTORS ($EXPECT_UBOOT_SIZE_SECTORS)"
		else
			bad "partition $UBOOT_PART_NUM size=$uboot_size != \$EXPECT_UBOOT_SIZE_SECTORS=$EXPECT_UBOOT_SIZE_SECTORS"
		fi
	fi
fi

# =============================================================================
# 2. The 0xA2 partition's head == the pinned uboot.img
# =============================================================================

extract_region() {  # extract_region START_SECTOR NBYTES OUTFILE -- exactly NBYTES to OUTFILE
	_sectors=$(( ($2 + 511) / 512 ))
	dd if="$img" bs=512 skip="$1" count="$_sectors" status=none 2>/dev/null | head -c "$2" > "$3"
}

looks_like_sha256() {
	_s=$1
	case $_s in
		*[!0-9a-fA-F]*) return 1 ;;
	esac
	[ "${#_s}" -eq 64 ]
}

uboot_file=""
uboot_hash_expect=""
uboot_size_expect=$STOCK_UBOOT_SIZE

ref=${uboot_ref:-${UBOOT_IMG:-${UBOOT_SHA256:-}}}
if [ -n "$ref" ] && [ -f "$ref" ]; then
	uboot_file=$ref
	uboot_size_expect=$(wc -c < "$uboot_file" | tr -d ' ')
elif [ -n "$ref" ] && looks_like_sha256 "$ref"; then
	uboot_hash_expect=$(printf '%s' "$ref" | tr 'A-F' 'a-f')
elif [ -n "$ref" ]; then
	echo "$prog: uboot reference '$ref' is neither an existing file nor a 64-hex-char sha256" >&2
	exit 2
else
	uboot_hash_expect=$STOCK_UBOOT_SHA256
	note "no uboot reference given -- using the pinned stock hash (ADR 0017 default channel)"
fi

if [ -n "$uboot_start" ]; then
	uboot_part_bytes=$(( uboot_size * 512 ))
	if [ "$uboot_part_bytes" -lt "$uboot_size_expect" ]; then
		bad "partition $UBOOT_PART_NUM is only $uboot_part_bytes bytes, smaller than the $uboot_size_expect-byte reference -- cannot contain it"
	else
		region="$work/p${UBOOT_PART_NUM}-head.bin"
		extract_region "$uboot_start" "$uboot_size_expect" "$region"

		if [ -n "$uboot_file" ]; then
			if cmp -s "$region" "$uboot_file"; then
				ok "partition $UBOOT_PART_NUM head == $uboot_file byte-for-byte ($uboot_size_expect bytes, cmp)"
			else
				bad "partition $UBOOT_PART_NUM head DIFFERS from $uboot_file (cmp) -- board would not boot after the next Linux update (updateboot dd's this over p$UBOOT_PART_NUM)"
			fi
		fi

		if [ -n "$uboot_hash_expect" ]; then
			region_hash=$(sha256sum "$region" | cut -d' ' -f1)
			if [ "$region_hash" = "$uboot_hash_expect" ]; then
				ok "partition $UBOOT_PART_NUM head sha256 == $uboot_hash_expect"
			else
				bad "partition $UBOOT_PART_NUM head sha256 = $region_hash, expected $uboot_hash_expect"
			fi
		fi
	fi
else
	note "skipping uboot.img head check -- partition $UBOOT_PART_NUM was not found above"
fi

# =============================================================================
# 3. FAT32 payload partition inventory == docs/verification/sdcard-payload.md
# =============================================================================

# extract_fence STDIN -> the content of the first ```...``` fenced block on stdin
extract_fence() {
	awk '
		/^```/ { n++; next }
		n==1   { print }
	'
}

sec1_expected="$work/sec1-expected.txt"
sec2_literal="$work/sec2-literal.txt"
sec2_patterns="$work/sec2-patterns.txt"
: > "$sec1_expected"; : > "$sec2_literal"; : > "$sec2_patterns"

sed -n '/^## 1\./,/^## 2\./p' "$inventory_doc" | extract_fence \
	| sed -e 's/\r$//' -e 's/[[:space:]]*$//' -e '/^$/d' > "$sec1_expected"

sed -n '/^## 2\./,/^## 3\./p' "$inventory_doc" | extract_fence \
	| sed -e 's/\r$//' -e 's/[[:space:]]*$//' -e '/^$/d' > "$work/sec2-raw.txt"
while IFS= read -r _line; do
	case $_line in
		*'*'*) printf '%s\n' "$_line" >> "$sec2_patterns" ;;
		*)     printf '%s\n' "$_line" >> "$sec2_literal" ;;
	esac
done < "$work/sec2-raw.txt"

sec1_count=$(wc -l < "$sec1_expected" | tr -d ' ')
if [ "$sec1_count" -eq 0 ]; then
	bad "no entries parsed from $inventory_doc's \"## 1. Base inventory\" fenced block -- doc format changed? see this script's header"
fi

expected_list="$work/expected.txt"
cp "$sec1_expected" "$expected_list"
if [ "$SDCARD_CORES" = 1 ]; then
	cat "$sec2_literal" >> "$expected_list"
fi
LC_ALL=C sort -u -o "$expected_list" "$expected_list"

read_actual_inventory() {  # read_actual_inventory START_SECTOR OUTFILE
	_start_sector=$1
	_outfile=$2
	_offset=$(( _start_sector * 512 ))

	if command -v mdir >/dev/null 2>&1; then
		if MTOOLS_SKIP_CHECK=1 mdir -i "${img}@@${_offset}" -b -/ :: \
			> "$work/mdir.out" 2> "$work/mdir.err"; then
			tr -d '\r' < "$work/mdir.out" \
				| sed -e 's#^::##' -e 's#^/##' -e '/^$/d' \
				| LC_ALL=C sort -u > "$_outfile"
			return 0
		fi
		echo "$prog: mdir failed reading partition at offset $_offset:" >&2
		sed 's/^/  /' "$work/mdir.err" >&2
		return 1
	fi

	if [ "$(id -u)" != 0 ]; then
		echo "$prog: neither mtools (mdir) nor root (for loop-mount) available -- cannot read the FAT32 payload partition" >&2
		echo "$prog: install mtools (mk-sdcard.sh's own build dependency) or run as root" >&2
		return 2
	fi
	if ! command -v losetup >/dev/null 2>&1 || ! command -v mount >/dev/null 2>&1; then
		echo "$prog: losetup/mount not found for the root loop-mount fallback" >&2
		return 2
	fi
	mnt="$work/fatmnt"
	mkdir -p "$mnt"
	loopdev=$(losetup --show -f -o "$_offset" "$img") || { echo "$prog: losetup failed" >&2; return 1; }
	mount -o ro "$loopdev" "$mnt" || { echo "$prog: mount of $loopdev failed" >&2; return 1; }
	( cd "$mnt" && find . -mindepth 1 \
		\( -type d -printf '%P/\n' \) -o -printf '%P\n' ) \
		| LC_ALL=C sort -u > "$_outfile"
	umount "$mnt"; mnt=""
	losetup -d "$loopdev"; loopdev=""
	return 0
}

cores_payload_bytes() {  # cores_payload_bytes START_SECTOR -> prints total bytes under
	# mister-payload/_Console/ to stdout. rc 0 = measured (possibly "0" if empty/missing --
	# caller decides what that means), rc 1 = tooling present but the read failed, rc 2 =
	# no usable tooling at all. Mirrors read_actual_inventory's mtools-then-loop-mount
	# fallback shape so the two stay easy to compare.
	_start_sector=$1
	_offset=$(( _start_sector * 512 ))

	if command -v mcopy >/dev/null 2>&1; then
		_coresdir="$work/cores-size"
		mkdir -p "$_coresdir"
		if MTOOLS_SKIP_CHECK=1 mcopy -i "${img}@@${_offset}" -s "::/mister-payload/_Console" "$_coresdir" \
			> "$work/mcopy.out" 2> "$work/mcopy.err"; then
			du -sb "$_coresdir" 2>/dev/null | cut -f1
			return 0
		fi
		echo "$prog: mcopy failed extracting mister-payload/_Console for the size check:" >&2
		sed 's/^/  /' "$work/mcopy.err" >&2
		return 1
	fi

	if [ "$(id -u)" = 0 ] && command -v losetup >/dev/null 2>&1 && command -v mount >/dev/null 2>&1; then
		_szmnt="$work/cores-szmnt"
		mkdir -p "$_szmnt"
		_szloop=$(losetup --show -f -o "$_offset" "$img") || { echo "$prog: losetup failed for the cores size check" >&2; return 1; }
		if ! mount -o ro "$_szloop" "$_szmnt"; then
			echo "$prog: mount of $_szloop failed for the cores size check" >&2
			losetup -d "$_szloop"
			return 1
		fi
		du -sb "$_szmnt/mister-payload/_Console" 2>/dev/null | cut -f1
		umount "$_szmnt"
		losetup -d "$_szloop"
		return 0
	fi

	echo "$prog: neither mtools (mcopy) nor root (for loop-mount) available -- cannot measure mister-payload/_Console size" >&2
	return 2
}

actual_list="$work/actual.txt"
inventory_read_ok=1
if [ -n "$data_start" ]; then
	read_rc=0
	read_actual_inventory "$data_start" "$actual_list" || read_rc=$?
	case $read_rc in
		0) : ;;
		2) echo "$prog: aborting -- required tooling missing (see message(s) above), inventory check not completed" >&2; exit 2 ;;
		*) bad "could not read the FAT32 payload partition's file inventory"; inventory_read_ok=0 ;;
	esac
else
	bad "cannot read the FAT32 payload partition's inventory -- partition $DATA_PART_NUM was not found above"
	inventory_read_ok=0
fi

if [ "$inventory_read_ok" -eq 1 ]; then
	actual_count=$(wc -l < "$actual_list" | tr -d ' ')
	note "FAT32 payload partition: $actual_count raw entries read"

	# Opaque directories (sdcard-payload.md §1.1): assert exist + non-empty against the RAW
	# actual listing, then drop their descendants (but keep the directory entry itself)
	# before the exact diff, since the doc deliberately does not enumerate their contents.
	filtered_actual="$work/actual-filtered.txt"
	cp "$actual_list" "$filtered_actual"
	for od in $OPAQUE_DIRS; do
		if grep -qxF "$od" "$actual_list"; then
			od_children=$(awk -v d="$od" 'index($0,d)==1 && $0!=d' "$actual_list" | grep -c . || true)
			if [ "$od_children" -gt 0 ]; then
				ok "opaque dir $od exists and is non-empty ($od_children entries, contents not individually enumerated -- sdcard-payload.md §1.1)"
			else
				bad "opaque dir $od exists but is EMPTY (expected non-empty -- sdcard-payload.md §1.1)"
			fi
		else
			bad "opaque dir $od is MISSING from the FAT32 payload partition"
		fi
		awk -v d="$od" 'index($0,d)==1 && $0!=d { next } { print }' "$filtered_actual" > "$work/actual-filtered.tmp"
		mv "$work/actual-filtered.tmp" "$filtered_actual"
	done

	if [ "$SDCARD_CORES" = 1 ]; then
		if grep -qxF "$CORES_DIR" "$actual_list"; then
			ok "$CORES_DIR exists (SDCARD_CORES=1)"

			cores_bytes=""
			cores_size_rc=0
			cores_bytes=$(cores_payload_bytes "$data_start") || cores_size_rc=$?
			case $cores_size_rc in
				0)
					case $cores_bytes in
						''|*[!0-9]*)
							bad "could not measure $CORES_DIR total size (non-numeric result '$cores_bytes')"
							;;
						*)
							if [ "$cores_bytes" -le "$EXPECT_CORES_MAX_BYTES" ]; then
								ok "$CORES_DIR total size $cores_bytes bytes <= \$EXPECT_CORES_MAX_BYTES ($EXPECT_CORES_MAX_BYTES, ~600 MiB cap -- sdcard-payload.md §2 / ADR 0020 §3)"
							else
								bad "$CORES_DIR total size $cores_bytes bytes EXCEEDS \$EXPECT_CORES_MAX_BYTES ($EXPECT_CORES_MAX_BYTES, ~600 MiB cap -- sdcard-payload.md §2 / ADR 0020 §3)"
							fi
							;;
					esac
					;;
				2) echo "$prog: aborting -- required tooling missing (see message(s) above), $CORES_DIR size check not completed" >&2; exit 2 ;;
				*) bad "could not measure $CORES_DIR total size (see message(s) above)" ;;
			esac

			cores_children="$work/cores-children.txt"
			awk -v d="$CORES_DIR" 'index($0,d)==1 && $0!=d && index(substr($0,length(d)+1),"/")==0 { print substr($0,length(d)+1) }' \
				"$actual_list" > "$cores_children"
			n_children=$(wc -l < "$cores_children" | tr -d ' ')
			if [ "$n_children" -eq 0 ]; then
				bad "$CORES_DIR exists but has no direct entries (SDCARD_CORES=1 expects *.rbf files)"
			fi
			while IFS= read -r pat; do
				[ -n "$pat" ] || continue
				pdir=${pat%/*}
				glob=${pat##*/}
				[ "${pdir}/" = "$CORES_DIR" ] || { note "ignoring unrecognised pattern line '$pat' in sdcard-payload.md §2"; continue; }
				bad_glob=0
				while IFS= read -r child; do
					# shellcheck disable=SC2254 # $glob is deliberately unquoted: it IS the
					# glob pattern from sdcard-payload.md §2 ("*.rbf"), matched against
					# each direct child of $CORES_DIR, not a literal string.
					case $child in
						$glob) : ;;
						*) bad "$CORES_DIR$child does not match pattern '$glob' (sdcard-payload.md §2)"; bad_glob=1 ;;
					esac
				done < "$cores_children"
				[ "$bad_glob" -eq 0 ] && ok "every entry directly under $CORES_DIR matches '$glob' ($n_children entries)"
			done < "$sec2_patterns"
		else
			bad "$CORES_DIR is MISSING (SDCARD_CORES=1 requires it)"
		fi
		# Drop _Console's contents from the exact diff below; its own dir line is already
		# in $expected_list (from sec2_literal) and gets diffed normally.
		awk -v d="$CORES_DIR" 'index($0,d)==1 && $0!=d { next } { print }' "$filtered_actual" > "$work/actual-filtered.tmp"
		mv "$work/actual-filtered.tmp" "$filtered_actual"
	fi

	LC_ALL=C sort -u -o "$filtered_actual" "$filtered_actual"

	missing="$work/missing.txt"
	extra="$work/extra.txt"
	comm -23 "$expected_list" "$filtered_actual" > "$missing"
	comm -13 "$expected_list" "$filtered_actual" > "$extra"

	if [ ! -s "$missing" ] && [ ! -s "$extra" ]; then
		exp_count=$(wc -l < "$expected_list" | tr -d ' ')
		ok "FAT32 payload partition inventory matches $inventory_doc exactly ($exp_count entries)"
	else
		bad "FAT32 payload partition inventory does not match $inventory_doc"
		if [ -s "$missing" ]; then
			note "MISSING (listed in the doc, absent from the image):"
			sed 's/^/    - /' "$missing" >&2
		fi
		if [ -s "$extra" ]; then
			note "UNEXPECTED (present in the image, not in the doc):"
			sed 's/^/    + /' "$extra" >&2
		fi
	fi
fi

if [ "$fail" -eq 0 ]; then
	echo "$prog: all assertions passed"
else
	echo "$prog: CONTRACT VIOLATED" >&2
fi
exit "$fail"
