#!/bin/bash
# mount_smb.sh -- mount an SMB/CIFS share from a NAS onto the MiSTer's SD card.
#
# Part of MiSTer Linux Modernization.
# https://github.com/mcfbytes/Buildroot_MiSTer
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version. Distributed WITHOUT ANY WARRANTY; see <https://www.gnu.org/licenses/>.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS RATHER THAN Scripts/cifs_mount.sh
# ---------------------------------------------------------------------------
# MiSTer-devel/Scripts_MiSTer's cifs_mount.sh cannot mount anything on a kernel
# newer than 6.7. Before doing any work it walks a hard-coded list of module
# FILENAMES --
#
#     KERNEL_MODULES="md4.ko|md5.ko|des_generic.ko|fscache.ko|cifs.ko"
#
# -- and requires every one of them to appear in
# /lib/modules/$(uname -r)/modules.builtin (or in lsmod). Four of the five are
# there on this image. fscache.ko is not, and no kernel >= 6.8 can ever provide
# it. Linux 6.8 merged fs/fscache/ into fs/netfs/ and, in the same move, changed
# CONFIG_FSCACHE from `tristate` to `bool`:
#
#     v6.7  fs/fscache/Kconfig    config FSCACHE / tristate
#           fs/fscache/Makefile   obj-$(CONFIG_FSCACHE) := fscache.o
#     v6.8  fs/netfs/Kconfig      config FSCACHE / bool, depends on NETFS_SUPPORT
#           fs/netfs/Makefile     netfs-$(CONFIG_FSCACHE) += fscache_*.o
#
# A `bool` symbol can only ever be y or n, never m -- so from 6.8 onward fscache
# is not a module under ANY configuration; its objects are linked into netfs.ko.
# The probe therefore reports
#
#     The current Kernel doesn't support CIFS (SAMBA).
#     Please update your MiSTer Linux system.
#
# on a kernel whose CIFS support is complete and working. (fscache was never
# required for CIFS in the first place -- that is CONFIG_CIFS_FSCACHE, which is
# unset on stock MiSTer too.) See docs/cifs-mount-fscache-probe.md.
#
# Rather than fork 991 lines of an actively-maintained upstream script, this is
# a clean reimplementation of the same job. The differences that matter:
#
#   * Asks the KERNEL what it supports (/proc/filesystems) instead of guessing
#     from module filenames. Correct whether cifs is built in or modular, on
#     any kernel version, forever.
#   * Boot automount goes only into /media/fat/linux/user-startup.sh, and the
#     block it writes is guarded on "$1". Upstream also falls back to writing
#     /etc/init.d/S99cifs_mount, which on this image is pointless -- a Linux
#     update reflashes the whole rootfs and takes any /etc/init.d entry with
#     it -- and its user-startup.sh block is unguarded, so it re-runs the mount
#     during shutdown when S99user calls user-startup.sh with "stop".
#   * No module downloading, no NetBIOS iptables hole-punching (this image
#     ships no /etc/iptables.conf, so S35iptables installs no rules and there
#     is no firewall to punch through), no NTP restart workaround.
#
# ---------------------------------------------------------------------------
# HOW IT GETS ONTO A CARD
# ---------------------------------------------------------------------------
# The same single route as this project's other Scripts (ADR 0026):
#
#   * install.sh                        -- onboarding, fetches all three
#   * update_linux_modernization.sh     -- replaces any that went missing
#   * scripts/fetch-sdcard-payload.sh   -- stages all three into sdcard.img
#   * uninstall.sh --remove-script      -- removes all three
#
# ---------------------------------------------------------------------------
# CONFIGURING IT
# ---------------------------------------------------------------------------
# Either edit the USER OPTIONS below, or -- better, because an image update
# replaces this file -- put the same KEY=VALUE lines in mount_smb.ini beside
# it. An existing cifs_mount.ini is read as a fallback, so migrating from
# cifs_mount.sh needs no retyping.
#
#   ./mount_smb.sh              mount now
#   ./mount_smb.sh --umount     unmount everything this script mounted
#   ./mount_smb.sh --help       usage

set -uo pipefail


#=========   USER OPTIONS   =========

# Your SMB server: NAS hostname or IP address. Required.
SERVER=""

# The share name on that server.
SHARE="MiSTer"

# Mount only this subdirectory of the share, instead of its root. Optional.
SHARE_DIRECTORY=""

# Credentials. Leave USERNAME blank for guest access.
USERNAME=""
PASSWORD=""
DOMAIN=""

# Where the share is mounted under /media/fat. Three forms:
#
#   "cifs"            one directory. //NAS/MiSTer -> /media/fat/cifs.
#                     Keep this name unless you have a reason not to: the
#                     MiSTer binary looks in /media/fat/cifs before it looks
#                     in /media/fat/games.
#   "Amiga|C64|NES"   a pipe-separated list. Each name is taken as a
#                     subdirectory of the share and mounted at that name
#                     under /media/fat.
#   "*"               every directory in the share except SPECIAL_DIRECTORIES.
LOCAL_DIR="cifs"

# Appended to the mount options, comma-separated, e.g. "vers=2.0" for an old
# NAS that will not negotiate SMB3, or "guest" if "sec=none" is refused.
ADDITIONAL_MOUNT_OPTIONS=""

# "true" to wait for the server to come up instead of failing immediately.
# Forced on for boot mounts.
WAIT_FOR_SERVER="false"

# "true" to mount at every boot, via /media/fat/linux/user-startup.sh.
MOUNT_AT_BOOT="false"


#========= ADVANCED OPTIONS =========

BASE_PATH="/media/fat"

# "true" makes ONE connection to the server and bind-mounts each directory out
# of it, instead of one CIFS connection per directory. Cheaper on the server
# and much faster when LOCAL_DIR names several directories.
SINGLE_CONNECTION="true"

# Never mounted when LOCAL_DIR="*". These are MiSTer's own, not the share's.
SPECIAL_DIRECTORIES="config|linux|System Volume Information"

# Boot-mount pacing. The delay gives the network stack a moment before the
# first probe; the timeouts bound how long a boot mount can hang around.
BOOT_START_DELAY_SECONDS="8"
NETWORK_READY_TIMEOUT_SECONDS="45"
SERVER_WAIT_TIMEOUT_SECONDS="60"

# Boot mounts have nowhere to print, so they print here.
BOOT_LOG_PATH="/tmp/mount_smb.log"


#========= CODE STARTS HERE =========

SCRIPT_NAME="mount_smb"
BOOT_ARG="--boot-start"
USER_STARTUP="/media/fat/linux/user-startup.sh"
USER_STARTUP_TEMPLATE="/media/fat/linux/_user-startup.sh"
TEMP_MOUNT="/tmp/$SCRIPT_NAME"

BEGIN_MARKER="# ${SCRIPT_NAME}.sh: BEGIN managed boot mount"
END_MARKER="# ${SCRIPT_NAME}.sh: END managed boot mount"

BOOT_START="false"
ACTION="mount"
MOUNT_FAILURES=0

# Every option a mount_smb.ini may set. An allow-list rather than a blanket
# "assign whatever the file contains" is what keeps a stray or malicious line
# in an ini from redefining PATH, IFS or anything else in this shell.
INI_KEYS=(
	SERVER SHARE SHARE_DIRECTORY USERNAME PASSWORD DOMAIN
	LOCAL_DIR ADDITIONAL_MOUNT_OPTIONS WAIT_FOR_SERVER MOUNT_AT_BOOT
	BASE_PATH SINGLE_CONNECTION SPECIAL_DIRECTORIES
	BOOT_START_DELAY_SECONDS NETWORK_READY_TIMEOUT_SECONDS
	SERVER_WAIT_TIMEOUT_SECONDS BOOT_LOG_PATH
)

usage() {
	cat <<EOF
usage: mount_smb.sh [--umount] [--help]

  (no option)   mount the share described by mount_smb.ini
  --umount      unmount everything this script mounted
  --help        this text

Configure it in mount_smb.ini beside this script. An existing cifs_mount.ini
is read as a fallback. Full documentation:
https://github.com/mcfbytes/Buildroot_MiSTer/blob/master/docs/cifs-mount-fscache-probe.md
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		"$BOOT_ARG")     BOOT_START="true" ;;
		--umount|-u)     ACTION="umount" ;;
		--help|-h)       usage; exit 0 ;;
		*)               echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

# Absolute path to this file, needed for the boot entry. $0 is whatever the
# Scripts menu invoked us as, which is frequently relative.
if SCRIPT_PATH=$(realpath "$0" 2>/dev/null) && [ -n "$SCRIPT_PATH" ]; then
	:
else
	SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi

# --- ini ------------------------------------------------------------------

trim() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

# Deliberately NOT `source`: an ini is data. Values are assigned with
# `printf -v`, which cannot execute anything, and only into names on the
# allow-list. A password containing $, #, spaces or quotes survives intact.
load_ini() {
	local file="$1" line key value allowed found
	[ -f "$file" ] || return 1

	while IFS= read -r line || [ -n "$line" ]; do
		line="${line%$'\r'}"
		case "$line" in *=*) ;; *) continue ;; esac

		key=$(trim "${line%%=*}")
		found="false"
		for allowed in "${INI_KEYS[@]}"; do
			[ "$key" = "$allowed" ] && { found="true"; break; }
		done
		[ "$found" = "true" ] || continue

		value=$(trim "${line#*=}")
		# Strip one layer of matching quotes, so both PASSWORD=s3cr#t and
		# PASSWORD="s3cr#t " round-trip. Unquoted values keep everything up
		# to end of line -- no inline-comment stripping, because # is a legal
		# password character and the allow-list already ignores comment lines.
		case "$value" in
			\"*\") value="${value#\"}"; value="${value%\"}" ;;
			\'*\') value="${value#\'}"; value="${value%\'}" ;;
		esac

		printf -v "$key" '%s' "$value"
	done < "$file"
	return 0
}

load_ini "${SCRIPT_PATH%.sh}.ini" ||
	load_ini "/media/fat/Scripts/${SCRIPT_NAME}.ini" ||
	load_ini "/media/fat/Scripts/cifs_mount.ini" ||
	true

if [ "$BOOT_START" = "true" ]; then
	if : >> "$BOOT_LOG_PATH" 2>/dev/null; then
		echo "==== $(date '+%Y-%m-%d %H:%M:%S') ${SCRIPT_NAME} boot start ====" >> "$BOOT_LOG_PATH"
		exec >> "$BOOT_LOG_PATH" 2>&1
	fi
fi

# --- pipe-separated lists -------------------------------------------------
#
# One directory per line on stdout. Upstream did this by setting IFS="|"
# globally for the whole script, which then silently changes how every later
# unquoted expansion splits; a local conversion has no such reach.
each() { printf '%s\n' "$1" | tr '|' '\n'; }

is_special() {
	local candidate="$1" special
	while IFS= read -r special; do
		[ -n "$special" ] || continue
		[ "$candidate" = "$special" ] && return 0
	done < <(each "$SPECIAL_DIRECTORIES")
	return 1
}

# --- capability -----------------------------------------------------------

# Ask the kernel what it supports, rather than inferring it from module
# filenames -- which is precisely what broke cifs_mount.sh.
#
# /proc/filesystems lists what the kernel has REGISTERED: built-in filesystems
# (CONFIG_CIFS=y, this image) and modules that are currently loaded. It does
# NOT list a module that is available but unloaded, so a bare grep would be a
# false negative on a modular kernel -- and would be stricter than the mount it
# is guarding, because mount autoloads: get_fs_type() calls
# request_module("fs-%s") for an unregistered type (fs/filesystems.c). Load it
# ourselves first, then let the second grep give the authoritative answer.
#
# modprobe's own exit status is deliberately ignored: whether it was missing,
# refused, or found nothing, the only question that matters is whether cifs is
# registered afterwards, and the grep answers exactly that.
kernel_supports_cifs() {
	grep -qE '(^|[[:space:]])cifs$' /proc/filesystems && return 0
	modprobe cifs >/dev/null 2>&1
	grep -qE '(^|[[:space:]])cifs$' /proc/filesystems
}

have_mount_helper() {
	[ -x /sbin/mount.cifs ] || [ -x /usr/sbin/mount.cifs ]
}

# --- mount table ----------------------------------------------------------

MOUNT_SOURCE_FOR_TARGET=""
MOUNT_TYPE_FOR_TARGET=""

# Parses `mount` output rather than /proc/mounts because the bind mounts this
# script makes are easier to attribute from the "SOURCE on TARGET type TYPE"
# form. Sets the two globals above as a side effect.
mount_info() {
	local want="$1" line source rest target type_rest
	MOUNT_SOURCE_FOR_TARGET=""
	MOUNT_TYPE_FOR_TARGET=""

	while IFS= read -r line; do
		source="${line%% on *}"
		rest="${line#* on }"
		[ "$rest" != "$line" ] || continue
		target="${rest%% type *}"
		[ "$target" = "$want" ] || continue
		type_rest="${rest#* type }"
		[ "$type_rest" != "$rest" ] || return 1
		MOUNT_SOURCE_FOR_TARGET="$source"
		MOUNT_TYPE_FOR_TARGET="${type_rest%% *}"
		return 0
	done < <(mount)
	return 1
}

is_mounted() { mount_info "$1"; }

# Must be called directly, never as $(fail ...) -- a command substitution runs
# it in a subshell, where the MOUNT_FAILURES increment is discarded and the
# script goes on to report success after failing to mount anything.
fail() { echo "$1"; MOUNT_FAILURES=$((MOUNT_FAILURES + 1)); return 1; }

mount_cifs_at() {
	local source="$1" target="$2" label="$3"
	mkdir -p "$target" >/dev/null 2>&1
	is_mounted "$target" && { echo "$label already mounted"; return 0; }
	mount -t cifs "$source" "$target" -o "$MOUNT_OPTIONS" ||
		{ fail "$label NOT mounted"; return 1; }
	echo "$label mounted"
}

bind_mount_at() {
	local source="$1" target="$2" label="$3"
	mkdir -p "$target" >/dev/null 2>&1
	is_mounted "$target" && { echo "$label already mounted"; return 0; }
	[ -d "$source" ] ||
		{ fail "$label NOT mounted (no such directory on the share)"; return 1; }
	mount --bind "$source" "$target" ||
		{ fail "$label NOT mounted"; return 1; }
	echo "$label mounted"
}

# --- unmount --------------------------------------------------------------

# Unmounts in the right order and only what we own: every bind mount whose
# SOURCE is under our temp mount first, then the temp mount itself, then any
# direct CIFS mount under BASE_PATH.
unmount_all() {
	local line source rest target n=0

	while IFS= read -r line; do
		source="${line%% on *}"
		rest="${line#* on }"
		[ "$rest" != "$line" ] || continue
		target="${rest%% type *}"
		case "$source" in "$TEMP_MOUNT"/*) ;; *) continue ;; esac
		umount "$target" >/dev/null 2>&1 &&
			{ echo "unmounted ${target##*/}"; n=$((n + 1)); } ||
			echo "could NOT unmount $target"
	done < <(mount)

	if is_mounted "$TEMP_MOUNT"; then
		umount "$TEMP_MOUNT" >/dev/null 2>&1 &&
			{ echo "unmounted $TEMP_MOUNT"; n=$((n + 1)); } ||
			echo "could NOT unmount $TEMP_MOUNT"
	fi

	while IFS= read -r line; do
		source="${line%% on *}"
		rest="${line#* on }"
		[ "$rest" != "$line" ] || continue
		target="${rest%% type *}"
		case "$target" in "$BASE_PATH"/*) ;; *) continue ;; esac
		case "${rest#* type }" in cifs*) ;; *) continue ;; esac
		umount "$target" >/dev/null 2>&1 &&
			{ echo "unmounted ${target##*/}"; n=$((n + 1)); } ||
			echo "could NOT unmount $target"
	done < <(mount)

	[ "$n" -eq 0 ] && echo "Nothing was mounted."
	return 0
}

if [ "$ACTION" = "umount" ]; then
	unmount_all
	echo "Done!"
	exit 0
fi

# --- boot entry -----------------------------------------------------------

# /media/fat/linux/user-startup.sh is the only boot hook worth using here: it
# lives on the FAT partition, so it survives the wholesale rootfs reflash that
# every Linux update performs. An /etc/init.d entry does not.
ensure_user_startup() {
	[ -x /etc/init.d/S99user ] || return 1
	if [ ! -e "$USER_STARTUP" ]; then
		if [ -e "$USER_STARTUP_TEMPLATE" ]; then
			cp "$USER_STARTUP_TEMPLATE" "$USER_STARTUP" || return 1
		else
			printf '#!/bin/sh\n\n' > "$USER_STARTUP" || return 1
		fi
	fi
	chmod +x "$USER_STARTUP" >/dev/null 2>&1 || true
	return 0
}

# Strips our block, and -- because both would target the same mount points --
# any boot entry left behind by Scripts/cifs_mount.sh.
strip_boot_entries() {
	awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
		$0 == b { skip = 1; next }
		$0 == e { skip = 0; next }
		skip    { next }
		$0 == "# cifs_mount: BEGIN managed boot mount" { legacy = 1; next }
		$0 == "# cifs_mount: END managed boot mount"   { legacy = 0; next }
		legacy  { next }
		index($0, "# Startup cifs_mount")        { next }
		index($0, "cifs_mount.sh --boot-start")  { next }
		{ print }
	' "$1"
}

write_boot_entry() {
	local tmp
	ensure_user_startup || return 1
	tmp="/tmp/${SCRIPT_NAME}_startup.$$"

	strip_boot_entries "$USER_STARTUP" > "$tmp" || { rm -f "$tmp"; return 1; }

	if [ "$MOUNT_AT_BOOT" = "true" ]; then
		# Guarded on "$1". S99user calls user-startup.sh with start, stop and
		# restart; without this case the mount would also be kicked off during
		# shutdown. Backgrounded so a slow or absent NAS never delays boot.
		#
		# shellcheck disable=SC2016
		# The single quotes are the point: ${1:-start} must reach
		# user-startup.sh literally, to be expanded THERE against the argument
		# S99user passes. Expanding it here would bake in this script's own $1.
		{
			printf '\n%s\n' "$BEGIN_MARKER"
			printf 'case "${1:-start}" in\n'
			printf '\tstart|restart) [ -x "%s" ] && "%s" %s & ;;\n' \
				"$SCRIPT_PATH" "$SCRIPT_PATH" "$BOOT_ARG"
			printf 'esac\n'
			printf '%s\n' "$END_MARKER"
		} >> "$tmp"
	fi

	if cmp -s "$tmp" "$USER_STARTUP"; then
		rm -f "$tmp"
		return 0
	fi

	cat "$tmp" > "$USER_STARTUP" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"
	chmod +x "$USER_STARTUP" >/dev/null 2>&1 || true

	if [ "$MOUNT_AT_BOOT" = "true" ]; then
		echo "Boot automount enabled ($USER_STARTUP)."
	else
		echo "Boot automount disabled."
	fi
	return 0
}

# Configuring the boot entry is separate from mounting, and happens first so
# that `MOUNT_AT_BOOT=false` still takes effect on a box whose NAS is down.
if [ "$BOOT_START" != "true" ]; then
	write_boot_entry || echo "Could not update $USER_STARTUP; carrying on."
fi

# --- preflight ------------------------------------------------------------

if [ -z "$SERVER" ]; then
	echo "Please configure"
	echo "this script by making"
	echo "${SCRIPT_NAME}.ini"
	echo "beside it, with at"
	echo "least SERVER= set."
	exit 1
fi

if ! kernel_supports_cifs; then
	echo "This kernel has no CIFS"
	echo "support (no cifs in"
	echo "/proc/filesystems)."
	exit 1
fi

if ! have_mount_helper; then
	echo "mount.cifs is missing."
	echo "This image should ship"
	echo "it; please report this."
	exit 1
fi

if [ "$BOOT_START" = "true" ]; then
	WAIT_FOR_SERVER="true"

	[ "${BOOT_START_DELAY_SECONDS:-0}" -gt 0 ] 2>/dev/null &&
		sleep "$BOOT_START_DELAY_SECONDS"

	# A global-scope IPv4 address is the honest "the network is usable" signal;
	# an interface can be up with only a link-local address for a long time.
	timeout="${NETWORK_READY_TIMEOUT_SECONDS:-45}"
	case "$timeout" in ''|*[!0-9]*) timeout=45 ;; esac
	waited=0
	echo "Waiting for the network"
	until ip -o -4 addr show up scope global 2>/dev/null | grep -q .; do
		if [ "$waited" -ge "$timeout" ]; then
			echo "No IPv4 address after ${timeout}s."
			exit 1
		fi
		sleep 1
		waited=$((waited + 1))
	done
fi

# --- resolve the server ---------------------------------------------------

is_ipv4() {
	case "$1" in
		*[!0-9.]*) return 1 ;;
		*.*.*.*)   return 0 ;;
		*)         return 1 ;;
	esac
}

resolve_server() {
	local name="$1" addr

	if command -v getent >/dev/null 2>&1; then
		addr=$(getent ahostsv4 "$name" 2>/dev/null | awk '/^[0-9]+\./ { print $1; exit }')
		[ -n "$addr" ] && { echo "$addr"; return 0; }
	fi

	if command -v nslookup >/dev/null 2>&1; then
		addr=$(nslookup "$name" 2>/dev/null | awk '
			/^Name:/ { found = 1; next }
			found { for (i = 1; i <= NF; i++)
				if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print $i; exit } }')
		[ -n "$addr" ] && { echo "$addr"; return 0; }
	fi

	# NetBIOS last: it only works on the local segment, and a DNS answer is
	# always the better one when there is one.
	if command -v nmblookup >/dev/null 2>&1; then
		addr=$(nmblookup "$name" 2>/dev/null | awk '/^[0-9]+\./ { print $1; exit }')
		[ -n "$addr" ] && { echo "$addr"; return 0; }
	fi

	return 1
}

server_wait_timeout="${SERVER_WAIT_TIMEOUT_SECONDS:-60}"
case "$server_wait_timeout" in ''|*[!0-9]*) server_wait_timeout=60 ;; esac

if is_ipv4 "$SERVER"; then
	if [ "$WAIT_FOR_SERVER" = "true" ]; then
		waited=0
		echo "Waiting for $SERVER"
		until ping -q -w1 -c1 "$SERVER" >/dev/null 2>&1; do
			if [ "$waited" -ge "$server_wait_timeout" ]; then
				echo "$SERVER unreachable after ${server_wait_timeout}s."
				exit 1
			fi
			sleep 1
			waited=$((waited + 1))
		done
	fi
else
	if [ "$WAIT_FOR_SERVER" = "true" ]; then
		waited=0
		echo "Looking up $SERVER"
		until resolved=$(resolve_server "$SERVER"); do
			if [ "$waited" -ge "$server_wait_timeout" ]; then
				echo "$SERVER not found after ${server_wait_timeout}s."
				exit 1
			fi
			sleep 1
			waited=$((waited + 1))
		done
	else
		resolved=$(resolve_server "$SERVER") || resolved=""
	fi
	if [ -z "$resolved" ]; then
		echo "$SERVER not found."
		exit 1
	fi
	SERVER="$resolved"
fi

# --- mount ----------------------------------------------------------------

if [ -z "$USERNAME" ]; then
	MOUNT_OPTIONS="sec=none"
else
	MOUNT_OPTIONS="username=$USERNAME,password=$PASSWORD"
	[ -n "$DOMAIN" ] && MOUNT_OPTIONS="$MOUNT_OPTIONS,domain=$DOMAIN"
fi
[ -n "$ADDITIONAL_MOUNT_OPTIONS" ] &&
	MOUNT_OPTIONS="$MOUNT_OPTIONS,$ADDITIONAL_MOUNT_OPTIONS"

MOUNT_SOURCE="//$SERVER/$SHARE"
[ -n "$SHARE_DIRECTORY" ] && MOUNT_SOURCE="$MOUNT_SOURCE/$SHARE_DIRECTORY"

# One directory, one CIFS mount, nothing else to arrange.
if [ "$LOCAL_DIR" != "*" ] && ! echo "$LOCAL_DIR" | grep -q '|'; then
	mount_cifs_at "$MOUNT_SOURCE" "$BASE_PATH/$LOCAL_DIR" "$LOCAL_DIR"

elif [ "$SINGLE_CONNECTION" != "true" ]; then
	# One CIFS connection per directory.
	if [ "$LOCAL_DIR" = "*" ]; then
		expanded=""
		for path in "$BASE_PATH"/*; do
			[ -d "$path" ] || continue
			name="${path##*/}"
			is_special "$name" && continue
			expanded="${expanded:+$expanded|}$name"
		done
		LOCAL_DIR="$expanded"
	fi
	while IFS= read -r dir; do
		[ -n "$dir" ] || continue
		mount_cifs_at "$MOUNT_SOURCE/$dir" "$BASE_PATH/$dir" "$dir"
	done < <(each "$LOCAL_DIR")

else
	# One CIFS connection, bind-mounted into place. Recover a stale temp mount
	# left by an interrupted run before reusing the path, otherwise the bind
	# mounts below would be made out of the wrong share.
	mkdir -p "$TEMP_MOUNT" >/dev/null 2>&1
	reuse="false"
	if is_mounted "$TEMP_MOUNT"; then
		if [ "$MOUNT_TYPE_FOR_TARGET" = "cifs" ] &&
		   [ "$MOUNT_SOURCE_FOR_TARGET" = "$MOUNT_SOURCE" ]; then
			echo "$MOUNT_SOURCE already mounted"
			reuse="true"
		else
			echo "Recovering a stale $TEMP_MOUNT"
			unmount_all >/dev/null
		fi
	fi

	if [ "$reuse" = "true" ] || mount_cifs_at "$MOUNT_SOURCE" "$TEMP_MOUNT" "$MOUNT_SOURCE"; then
		if [ "$LOCAL_DIR" = "*" ]; then
			expanded=""
			for path in "$TEMP_MOUNT"/*; do
				[ -d "$path" ] || continue
				name="${path##*/}"
				is_special "$name" && continue
				expanded="${expanded:+$expanded|}$name"
			done
			LOCAL_DIR="$expanded"
			[ -n "$LOCAL_DIR" ] || echo "The share has no directories to mount."
		fi
		while IFS= read -r dir; do
			[ -n "$dir" ] || continue
			bind_mount_at "$TEMP_MOUNT/$dir" "$BASE_PATH/$dir" "$dir"
		done < <(each "$LOCAL_DIR")
	fi
fi

if [ "$MOUNT_FAILURES" -gt 0 ]; then
	echo "Done, with $MOUNT_FAILURES failure(s)."
	exit 1
fi

echo "Done!"
exit 0
