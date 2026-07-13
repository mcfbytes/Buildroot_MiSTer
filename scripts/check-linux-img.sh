#!/bin/sh
#
# check-linux-img.sh — assert the `linux.img` contract (P2.5 / A9, ADR 0015).
#
# Two independent things this proves about a built linux.img, neither of
# which "it mounted fine once" would catch:
#
#  1. PINNED EXT4 FEATURE SET / LABEL / UUID. configs/mister_de10nano_defconfig's
#     BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS spells these out explicitly (its own
#     header explains why: e2fsprogs' own mke2fs.conf defaults already drift
#     from what stock's linux.img actually has, and a future e2fsprogs bump
#     could drift further). This script is the build-time proof that the
#     option string actually landed in the artifact, the same role
#     check-zimage-dtb.sh plays for the zImage/DTB concatenation contract.
#     The expected values below MUST be kept in sync with that defconfig by
#     hand -- there is no single source of truth to derive them from at
#     build time (dumpe2fs reads the finished image, not the mkfs command
#     line that produced it).
#
#  2. NO ssh_host_* PRIVATE KEYS IN THE IMAGE (ADR 0015). Stock bakes
#     /etc/ssh/ssh_host_{rsa,ecdsa,ed25519,dsa}_key into linux.img -- the
#     same four private keys on every MiSTer on Earth. We generate host keys
#     at first boot into a SEPARATE ext4 image on the FAT partition
#     (S49sshd, P2.3) specifically so linux.img itself carries no secret and
#     stays reproducible. This is simultaneously a SECURITY assertion (don't
#     ship a key) and a REPRODUCIBILITY assertion (a baked-in key would be
#     regenerated, and therefore different, on every build). Checked against
#     the actual image bytes via debugfs, not against the source tree --
#     the source tree proves intent, the image proves what gets flashed.
#
# Usage: scripts/check-linux-img.sh <linux.img> [HOST_SBIN_DIR]
#   HOST_SBIN_DIR defaults to <dirname linux.img>/../host/sbin (Buildroot's
#   own BINARIES_DIR/../host/sbin layout); override for standalone use.
# Exit:  0 = all assertions pass, 1 = a contract violation, 2 = usage/IO error.

set -eu

prog=${0##*/}
fail=0

# --- the pinned contract -- MUST match configs/mister_de10nano_defconfig ----
EXPECT_LABEL="rootfs"
EXPECT_UUID="71916572-439f-448e-b8d8-12b0a032fa56"
EXPECT_HASH_SEED="9afc615c-c310-4e03-ada9-613522e83ae6"
EXPECT_SIZE_BYTES=536870912   # 512 MiB, BR2_TARGET_ROOTFS_EXT2_SIZE="512M"
# Sorted (LC_ALL=C sort) so the comparison below doesn't depend on dumpe2fs's
# own (enum-order, not alphabetical) print order.
EXPECT_FEATURES_SORTED="64bit
dir_index
dir_nlink
ext_attr
extent
extra_isize
filetype
flex_bg
has_journal
huge_file
large_file
metadata_csum
resize_inode
sparse_super"

usage() {
	echo "usage: $prog <linux.img> [HOST_SBIN_DIR]" >&2
	exit 2
}

note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; fail=1; }

[ $# -ge 1 ] || usage
img=$1
[ -f "$img" ] || { echo "$prog: no such file: $img" >&2; exit 2; }

img_dir=$(cd "$(dirname "$img")" && pwd)
host_sbin=${2:-"$img_dir/../host/sbin"}

find_tool() {
	# $1 = tool name
	if [ -x "$host_sbin/$1" ]; then
		echo "$host_sbin/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	else
		echo "$prog: cannot find '$1' (looked in $host_sbin and PATH)" >&2
		exit 2
	fi
}

dumpe2fs_bin=$(find_tool dumpe2fs)
debugfs_bin=$(find_tool debugfs)

printf '%s: %s (%s bytes)\n' "$prog" "$img" "$(wc -c <"$img" | tr -d ' ')"

# --- 0. exact size ------------------------------------------------------------
size=$(wc -c <"$img" | tr -d ' ')
if [ "$size" -eq "$EXPECT_SIZE_BYTES" ]; then
	ok "size == $EXPECT_SIZE_BYTES bytes (512 MiB)"
else
	bad "size $size != expected $EXPECT_SIZE_BYTES bytes"
fi

# --- 1. dumpe2fs -h: label / UUID / hash seed / feature set ------------------
hdr=$("$dumpe2fs_bin" -h "$img" 2>/dev/null) || { echo "$prog: dumpe2fs -h failed on $img" >&2; exit 2; }

label=$(printf '%s\n' "$hdr" | sed -n 's/^Filesystem volume name:[[:space:]]*//p')
if [ "$label" = "$EXPECT_LABEL" ]; then
	ok "volume label = '$EXPECT_LABEL'"
else
	bad "volume label = '$label', expected '$EXPECT_LABEL'"
fi

uuid=$(printf '%s\n' "$hdr" | sed -n 's/^Filesystem UUID:[[:space:]]*//p')
if [ "$uuid" = "$EXPECT_UUID" ]; then
	ok "filesystem UUID = $EXPECT_UUID (pinned)"
else
	bad "filesystem UUID = '$uuid', expected '$EXPECT_UUID'"
fi

hseed=$(printf '%s\n' "$hdr" | sed -n 's/^Directory Hash Seed:[[:space:]]*//p')
if [ "$hseed" = "$EXPECT_HASH_SEED" ]; then
	ok "directory hash seed = $EXPECT_HASH_SEED (pinned)"
else
	bad "directory hash seed = '$hseed', expected '$EXPECT_HASH_SEED'"
fi

features_line=$(printf '%s\n' "$hdr" | sed -n 's/^Filesystem features:[[:space:]]*//p')
features_sorted=$(printf '%s\n' "$features_line" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort)
note "features (as built): $features_line"
if [ "$features_sorted" = "$EXPECT_FEATURES_SORTED" ]; then
	ok "feature set matches the pinned 14-feature stock-derived list exactly"
else
	bad "feature set does not match the pinned list"
	note "expected (sorted): $(printf '%s' "$EXPECT_FEATURES_SORTED" | tr '\n' ' ')"
	note "got      (sorted): $(printf '%s' "$features_sorted" | tr '\n' ' ')"
fi

# --- 2. ADR 0015: no ssh_host_* private keys anywhere in the image -----------
dump_dir=$(mktemp -d "${TMPDIR:-/tmp}/check-linux-img.XXXXXX")
trap 'rm -rf "$dump_dir"' EXIT

# rdump copies the WHOLE image out to a real directory tree so we can grep it
# with ordinary tools; -R "..." runs one command non-interactively. Run as an
# unprivileged user, `chown` inside rdump fails loudly on stderr for every
# non-root-owned file -- expected noise, not a fault; only stdout/exit status
# and the dumped tree's contents are load-bearing here.
"$debugfs_bin" -R "rdump / $dump_dir" "$img" >/dev/null 2>"$dump_dir.rdump.log" || true

# A silent debugfs failure must NOT read as "no keys found". If the dump did not
# actually produce the image's tree, the ssh_host_* scan below would trivially
# find nothing and pass -- a false all-clear on a SECURITY invariant. Require
# proof the dump is real (every ext4 rootfs has these) before trusting it.
if [ ! -d "$dump_dir/etc" ] || [ ! -d "$dump_dir/usr" ]; then
	bad "debugfs rdump did not produce a readable rootfs tree from $img"
	note "(no $dump_dir/etc or /usr) -- cannot verify the no-private-keys invariant"
	note "debugfs stderr:"; sed 's/^/    /' "$dump_dir.rdump.log" 2>/dev/null | head -5
else
	found=$(find "$dump_dir" -iname 'ssh_host_*' 2>/dev/null || true)
	if [ -z "$found" ]; then
		ok "no ssh_host_* files anywhere in the image (ADR 0015)"
	else
		bad "ssh_host_* file(s) found IN THE IMAGE -- this ships a private key:"
		printf '%s\n' "$found" | while IFS= read -r f; do note "$f"; done
	fi
fi
rm -f "$dump_dir.rdump.log"

# Belt-and-suspenders: the specific mount point ADR 0015 names must exist and
# be EMPTY in the image (keys are generated at first boot into a *separate*
# ext4 image on the FAT data partition, not into linux.img -- see the ADR).
keys_dir_listing=$("$debugfs_bin" -R "ls -p /etc/ssh_keys" "$img" 2>/dev/null || true)
# debugfs -p output is one dir-entry-record per line: /ino/mode/uid/gid/name/len/
# "." and ".." are the only allowed entries; a hidden .gitkeep is tolerated
# (it is what makes the empty dir exist in a git-managed overlay -- P2.3).
#
# The mount point MUST exist: if /etc/ssh_keys is absent, first-boot key
# persistence has nowhere to mount and SSH degrades (S50sshd falls back to
# ephemeral keys). A missing dir makes `debugfs ls` fail -> empty output, which
# must read as a FAILURE, not as "empty and fine". Every real directory listing
# contains at least "." and "..", so require them as proof of existence.
if ! printf '%s\n' "$keys_dir_listing" | grep -Eq '/\.//$'; then
	bad "/etc/ssh_keys is MISSING from the image (mount point absent -- ADR 0015 key persistence would fail at boot)"
	note "debugfs ls output was: ${keys_dir_listing:-<empty>}"
else
	extra_entries=$(printf '%s\n' "$keys_dir_listing" | grep -Ev '/\.//$|/\.\.//$|/\.gitkeep/' | grep -c '/' || true)
	if [ "${extra_entries:-0}" -eq 0 ]; then
		ok "/etc/ssh_keys is present and empty in the image (keys are runtime state, not build output)"
	else
		bad "/etc/ssh_keys is not empty in the image:"
		note "$keys_dir_listing"
	fi
fi

if [ "$fail" -eq 0 ]; then
	echo "$prog: all assertions passed"
else
	echo "$prog: CONTRACT VIOLATED" >&2
fi
exit "$fail"
