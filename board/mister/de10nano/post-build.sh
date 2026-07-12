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
