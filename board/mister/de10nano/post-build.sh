#!/bin/sh
#
# post-build.sh <target-dir> [args...]
#
# Runs after the target filesystem is assembled, before image generation
# (BR2_ROOTFS_POST_BUILD_SCRIPT). Reproducible: no timestamps, no randomness.
#
# WHY THIS EXISTS — root password.
# We need a FIXED, pre-hashed root password so the build stays byte-reproducible
# (P2.5 / A9). BR2_TARGET_GENERIC_ROOT_PASSWD cannot carry a pre-hashed value
# reliably: the `$` in a "$5$salt$hash" string is eaten by make variable
# expansion before skeleton-init-common.mk's pre-encrypted detection
# (`$1$`/`$5$`/`$6$`) runs, so it silently falls through and re-hashes the
# mangled string with a RANDOM salt -- both wrong (unknown password) and
# non-reproducible. We therefore leave BR2_TARGET_GENERIC_ROOT_PASSWD empty and
# pin root's shadow entry here, surgically, where nothing can mangle it.
#
# The hash below is SHA-256 crypt of "1" with a fixed salt (openssl passwd -5
# -salt MiSTer618 1). "1" is STOCK PARITY -- the stock MiSTer image ships root
# password "1" -- so nothing changes for existing users, and SSH/console login
# is root:1 exactly as on stock. This is deliberately weak, matching stock;
# hardening it (and proftpd, and CONFIG_SECCOMP) is the beyond-parity security
# pass tracked separately, to be done AFTER parity is proven, not during it.

set -e

TARGET_DIR="${1:?post-build.sh: target dir argument missing}"
SHADOW="${TARGET_DIR}/etc/shadow"

# SHA-256 crypt of "1", fixed salt "MiSTer618" -> reproducible.
# shellcheck disable=SC2016  # literal crypt hash; the $ must NOT expand
ROOT_HASH='$5$MiSTer618$yiHxlAfaTCausfxfpep3MtaVqiqNTwl/tYeg3FF8rb1'

if [ ! -f "$SHADOW" ]; then
	echo "post-build.sh: ERROR: $SHADOW not found" >&2
	exit 1
fi

# Replace ONLY root's password field (2nd colon-field), leaving every other
# field and every other user (sshd privsep, ntp, messagebus, ...) untouched.
# awk, not sed, so the many '$' and '/' in the hash need no escaping.
awk -F: -v OFS=: -v h="$ROOT_HASH" \
	'$1=="root"{$2=h} {print}' "$SHADOW" > "$SHADOW.tmp"
mv "$SHADOW.tmp" "$SHADOW"
chmod 0640 "$SHADOW" 2>/dev/null || true

# Fail loudly if root did not end up with our hash (e.g. no root line).
if ! grep -q "^root:${ROOT_HASH}:" "$SHADOW"; then
	echo "post-build.sh: ERROR: failed to set root password hash in $SHADOW" >&2
	exit 1
fi
echo "post-build.sh: pinned root password (stock-parity '1', fixed salt)"

# --- /MiSTer.version (P2.6 / A10) ---------------------------------------------
# At the rootfs ROOT (/MiSTer.version), a 6-char YYMMDD stamp. This is what the
# Downloader reads from the RUNNING system to decide whether to apply a linux
# update. It reads it with a bare f.read() and NO .strip(), comparing against
# the last 6 chars of the db entry's version -- so it must be EXACTLY 6 bytes
# with NO trailing newline. `echo` would append \n, which never matches any db
# version and makes the box re-flash on every Downloader run, forever. Use
# printf '%s'. Version source, in priority order:
#   1. MISTER_VERSION (6-digit YYMMDD) exported by the RELEASE workflow from the
#      release tag. This makes /MiSTer.version DISTINCT per release AND equal to
#      the db.json entry's version, so the Downloader -- which compares this
#      against the db version's last 6 chars -- sees the box as up to date after
#      applying an update and does NOT re-flash on every run. This is the durable
#      fix for the constant-/MiSTer.version problem (P4.5 / ADR 0018): the stamp
#      used to come only from SOURCE_DATE_EPOCH, which is pinned to Buildroot's
#      commit and therefore identical across releases.
#   2. Otherwise, SOURCE_DATE_EPOCH's date -- constant per Buildroot pin, which is
#      exactly what keeps NON-release builds (CI push, local, the P4.3
#      reproducibility double-build) byte-reproducible (P2.5/A9). A release
#      pins MISTER_VERSION to a fixed tag date, so releases stay reproducible too.
if [ -n "${MISTER_VERSION:-}" ]; then
	VERSION_DATE="$MISTER_VERSION"
else
	VERSION_DATE="$(date -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%y%m%d 2>/dev/null \
		|| date -u -r "${SOURCE_DATE_EPOCH:-$(date +%s)}" +%y%m%d 2>/dev/null \
		|| date -u +%y%m%d)"
fi
# Guard the (external) override: exactly 6 digits YYMMDD, else fail the build
# rather than ship a version the Downloader could never match.
case "$VERSION_DATE" in
	[0-9][0-9][0-9][0-9][0-9][0-9]) : ;;
	*) echo "post-build.sh: ERROR: version must be 6 digits YYMMDD (got '$VERSION_DATE'; check MISTER_VERSION)" >&2; exit 1 ;;
esac
printf '%s' "$VERSION_DATE" > "$TARGET_DIR/MiSTer.version"

# Self-check A10: exactly 6 bytes, and the last byte is not a newline.
_n=$(wc -c < "$TARGET_DIR/MiSTer.version")
if [ "$_n" -ne 6 ] || [ "$(tail -c1 "$TARGET_DIR/MiSTer.version" | od -An -tx1 | tr -d ' ')" = "0a" ]; then
	echo "post-build.sh: ERROR: /MiSTer.version must be exactly 6 bytes, no newline (got $_n bytes)" >&2
	exit 1
fi
echo "post-build.sh: wrote /MiSTer.version = $VERSION_DATE (6 bytes, no newline)"

# --- Canonical update-channel copies (/usr/share/mister-linux-modernization) ---
# S05mlm pushes these onto /media/fat on every boot. They live in the ROOT
# FILESYSTEM on purpose, because that is the half of the card this project
# actually controls: /media/fat is rewritten by Update All, edited by users and
# survives a reflash, whereas linux.img is replaced wholesale on every release.
#
# That inversion is the whole point. It is also the ONLY way to ship a corrected
# updater script to an existing card: a release_YYYYMMDD.7z can carry nothing but
# files/linux/**, so it can never write /media/fat/Scripts/ -- but it carries
# linux.img, and linux.img carries these. Shipping a fixed script is therefore a
# normal image update, and db.json's files{} can stay empty forever (which keeps
# the published document tiny, per docs/db-json-versioning.md).
#
# Sourced from the SAME board/mister/de10nano/fat-payload/ tree that
# scripts/fetch-sdcard-payload.sh stages onto sdcard.img, so the card image and
# the rootfs can never disagree about what the current script is.
#
# BR2_EXTERNAL_MISTER_PATH is exported into post-build scripts by Buildroot
# (external.desc: name = MISTER). Fail loudly rather than silently shipping an
# image whose S05mlm finds no canonical copy and quietly does nothing.
: "${BR2_EXTERNAL_MISTER_PATH:?post-build.sh: BR2_EXTERNAL_MISTER_PATH not set}"

MLM_SRC="$BR2_EXTERNAL_MISTER_PATH/board/mister/de10nano/fat-payload"
MLM_DST="$TARGET_DIR/usr/share/mister-linux-modernization"

[ -d "$MLM_SRC" ] || {
	echo "post-build.sh: ERROR: $MLM_SRC not found" >&2
	exit 1
}

rm -rf "$MLM_DST"
mkdir -p "$MLM_DST/linux"

for _f in Scripts/update_linux_modernization.sh downloader.ini linux/user-startup.sh; do
	[ -f "$MLM_SRC/$_f" ] || {
		echo "post-build.sh: ERROR: missing update-channel source file $MLM_SRC/$_f" >&2
		exit 1
	}
done

# Flattened: S05mlm looks for update_linux_modernization.sh at the top of
# MLM_DST, not under a Scripts/ subdirectory.
cp -f "$MLM_SRC/Scripts/update_linux_modernization.sh" "$MLM_DST/update_linux_modernization.sh"
cp -f "$MLM_SRC/downloader.ini"                        "$MLM_DST/downloader.ini"
cp -f "$MLM_SRC/linux/user-startup.sh"                 "$MLM_DST/linux/user-startup.sh"

chmod 0755 "$MLM_DST/update_linux_modernization.sh" "$MLM_DST/linux/user-startup.sh"
chmod 0644 "$MLM_DST/downloader.ini"

# Fixed mtimes: BR2_ROOTFS_OVERLAY files get theirs from git checkout time, and
# these are copied by hand, so pin them to SOURCE_DATE_EPOCH to keep the image
# byte-reproducible (P2.5 / A9).
if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
	find "$MLM_DST" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} + 2>/dev/null || true
fi

echo "post-build.sh: staged canonical update-channel copies into /usr/share/mister-linux-modernization"
