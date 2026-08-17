#!/usr/bin/env bash
#
# scripts/test-mount-smb.sh — sandboxed functional test of
# board/mister/de10nano/fat-payload/Scripts/mount_smb.sh.
#
# WHY THIS EXISTS. mount_smb.sh replaces Scripts_MiSTer's cifs_mount.sh, which
# this image cannot run (docs/cifs-mount-fscache-probe.md). Three of its
# properties are the reason it exists at all, and none of them is visible to
# ci-tests.sh's rootfs.tar checks, which can only see that a file shipped:
#
#   1. The kernel capability gate reads /proc/filesystems, NOT a hard-coded list
#      of module filenames. That is the whole bug fix; a regression here puts
#      the image straight back to "The current Kernel doesn't support CIFS".
#   2. The boot block it writes into user-startup.sh is guarded on "$1". S99user
#      calls user-startup.sh with start, stop AND restart, so an unguarded block
#      -- upstream's -- also fires a mount during shutdown.
#   3. The ini is parsed as DATA. It holds a password, so a value containing
#      $, #, spaces or quotes has to survive intact, and a stray key must not be
#      able to redefine PATH or IFS in the script's own shell.
#
# It also pins the subshell trap in the failure counter: MOUNT_FAILURES is
# incremented by a function, and calling that function in a command
# substitution would silently discard every increment and report success after
# mounting nothing.
#
# HOW. The script is copied into a throwaway sandbox with its absolute paths
# (/media/fat, /etc/init.d/S99user, /proc/filesystems, /sbin, /tmp) rewritten to
# point inside it, and mount/umount/modprobe/ip/ping/nslookup/nmblookup/getent
# are stubbed on PATH. The mount stub doubles as the mount table: called with no
# arguments it prints one, called with arguments it records the call and appends
# to it. Nothing here needs a build, a board, or a network.
#
# Usage: scripts/test-mount-smb.sh
#   Exit 0 iff every case passed.

# shellcheck disable=SC2016,SC2030,SC2031
# Both are the mechanism here, not accidents:
#   SC2016  single-quoted $ is deliberate throughout. This file WRITES shell
#           scripts (the S99user stub, the _user-startup.sh template) and
#           asserts on a password that literally contains '$'. Expanding any of
#           it here would destroy exactly what is under test.
#   SC2030/1  every case runs the script inside ( ) with its own PATH so the
#           stubs win and nothing carries between cases -- same shape as
#           test-timezone.sh.

set -u
# Deliberately not -e: run every case and report the whole picture, same
# rationale as ci-tests.sh and test-timezone.sh.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/board/mister/de10nano/fat-payload/Scripts/mount_smb.sh"

if [ ! -f "$SRC" ]; then
	echo "test-mount-smb.sh: ERROR: $SRC not found" >&2
	exit 2
fi

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (want '$2', got '$1')"; fi; }
contains() {
	case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac
}
lacks() {
	case "$1" in *"$2"*) bad "$3 (unexpected '$2')" ;; *) ok "$3" ;; esac
}

# --------------------------------------------------------------------------
# Sandbox
# --------------------------------------------------------------------------
SB=""
new_sandbox() {
	SB="$(mktemp -d)"
	mkdir -p "$SB/media/fat/Scripts" "$SB/media/fat/linux" "$SB/etc/init.d" \
	         "$SB/proc" "$SB/bin" "$SB/sbin" "$SB/usr/sbin" "$SB/tmp"

	# Rewrite the absolute paths. ORDER MATTERS, twice over, and both orderings
	# are load-bearing rather than incidental:
	#
	#   * "/tmp/ must go first. $SB is itself under /tmp, so once any rule has
	#     inserted it, a later /tmp rule would rewrite the prefix it just wrote
	#     and produce $SB/$SB/... . Doing it first is the fix: no rule after it
	#     matches /tmp.
	#   * /usr/sbin/mount.cifs must go before /sbin/mount.cifs, which is a
	#     substring of it.
	#
	# /media/fat needs only one rule -- every longer path that contains it
	# (linux/user-startup.sh, Scripts/) falls out of the same substitution.
	sed -e "s#\"/tmp/#\"$SB/tmp/#g" \
	    -e "s#/media/fat#$SB/media/fat#g" \
	    -e "s#/etc/init.d/S99user#$SB/etc/init.d/S99user#g" \
	    -e "s#/proc/filesystems#$SB/proc/filesystems#g" \
	    -e "s#/usr/sbin/mount.cifs#$SB/usr/sbin/mount.cifs#g" \
	    -e "s#\([^r]\)/sbin/mount.cifs#\1$SB/sbin/mount.cifs#g" \
	    "$SRC" > "$SB/media/fat/Scripts/mount_smb.sh"
	chmod +x "$SB/media/fat/Scripts/mount_smb.sh"

	# The pieces of the image the script legitimately depends on.
	printf '#!/bin/sh\nUSER_SCRIPT="%s/media/fat/linux/user-startup.sh"\n[ -f "$USER_SCRIPT" ] && "$USER_SCRIPT" "$1"\n' \
		"$SB" > "$SB/etc/init.d/S99user"
	chmod +x "$SB/etc/init.d/S99user"
	printf '#!/bin/sh\n\necho "***" $1 "***"\n' > "$SB/media/fat/linux/_user-startup.sh"
	printf '#!/bin/sh\n' > "$SB/sbin/mount.cifs"
	chmod +x "$SB/sbin/mount.cifs"
	printf 'nodev\tsysfs\n\text4\nnodev\tcifs\nnodev\tsmb3\n' > "$SB/proc/filesystems"

	: > "$SB/mounts"
	: > "$SB/calls"

	# mount(8) stub: no arguments prints the mount table, arguments record the
	# call and extend it. MOUNT_SMB_TEST_FAIL=1 makes every mount attempt fail,
	# which is how the failure counter gets exercised.
	cat > "$SB/bin/mount" <<STUB
#!/bin/sh
if [ "\$#" -eq 0 ]; then cat "$SB/mounts"; exit 0; fi
echo "\$*" >> "$SB/calls"
[ "\${MOUNT_SMB_TEST_FAIL:-0}" = "1" ] && exit 1
if [ "\$1" = "--bind" ]; then
	echo "\$2 on \$3 type none (rw,bind)" >> "$SB/mounts"
else
	# mount -t cifs SOURCE TARGET -o OPTIONS
	echo "\$3 on \$4 type cifs (\$6)" >> "$SB/mounts"
fi
exit 0
STUB
	cat > "$SB/bin/umount" <<STUB
#!/bin/sh
grep -v " on \$1 type " "$SB/mounts" > "$SB/mounts.new" 2>/dev/null
mv -f "$SB/mounts.new" "$SB/mounts"
exit 0
STUB
	# Resolution stubs fail: every case here uses an IP literal for SERVER, so
	# a stub that answered would only mask a wrong code path being taken.
	for stub in modprobe getent nslookup nmblookup; do
		printf '#!/bin/sh\nexit 1\n' > "$SB/bin/$stub"
	done
	# ping succeeds: WAIT_FOR_SERVER is forced on for boot mounts, and a failing
	# ping would park the boot case in its retry loop for SERVER_WAIT_TIMEOUT.
	printf '#!/bin/sh\nexit 0\n' > "$SB/bin/ping"
	printf '#!/bin/sh\necho "2: eth0    inet 192.168.0.50/24 scope global eth0"\n' > "$SB/bin/ip"
	chmod +x "$SB/bin/"*
}

drop_sandbox() { [ -n "$SB" ] && rm -rf "$SB"; SB=""; }

# Runs the sandboxed script with the stubs in front of PATH.
run_smb() {
	( PATH="$SB/bin:$PATH"; cd "$SB/media/fat/Scripts" && ./mount_smb.sh "$@" 2>&1 )
}

ini() { printf '%s\n' "$@" > "$SB/media/fat/Scripts/mount_smb.ini"; }

# The boot block backgrounds the mount, so the assertion has to wait for it.
# Polls rather than sleeping a fixed amount: the delay this is really waiting
# out is BOOT_START_DELAY_SECONDS, which the cases set to 0, and a poll keeps
# the test fast without becoming a race on a loaded machine.
wait_for_calls() {
	local waited=0
	while [ "$waited" -lt 100 ]; do
		[ -s "$SB/calls" ] && return 0
		sleep 0.1
		waited=$((waited + 1))
	done
	return 1
}

# --------------------------------------------------------------------------
echo "test-mount-smb.sh"
echo

echo "shell syntax"
if bash -n "$SRC" 2>/dev/null; then ok "bash -n"; else bad "bash -n"; fi
if command -v shellcheck >/dev/null 2>&1; then
	if shellcheck -S warning "$SRC" >/dev/null 2>&1; then
		ok "shellcheck clean"
	else
		bad "shellcheck"
	fi
else
	echo "  skip  shellcheck (not installed)"
fi

# --------------------------------------------------------------------------
echo
echo "the bug this script exists to fix"
new_sandbox
ini 'SERVER=192.168.0.9'
out="$(run_smb)"
lacks "$out" "doesn't" "no 'The current Kernel doesn't support CIFS' on a CIFS-capable kernel"
contains "$out" "Done!" "mounts when /proc/filesystems lists cifs"
# The precise regression: a kernel with CIFS but no fscache.ko anywhere must
# still mount. The sandbox has no modules.builtin at all, which is the strongest
# form of that -- the old probe could not have passed here under any reading.
if [ ! -e "$SB/lib/modules" ]; then
	ok "gate consults no module list (none exists in the sandbox)"
else
	bad "gate consults a module list"
fi
if grep -q 'sec=none' "$SB/calls"; then ok "guest mount uses sec=none"; else bad "guest mount options"; fi
contains "$(cat "$SB/calls")" "-t cifs //192.168.0.9/MiSTer $SB/media/fat/cifs" "mounts share at LOCAL_DIR"
drop_sandbox

new_sandbox
printf 'nodev\tsysfs\n\text4\n' > "$SB/proc/filesystems"   # a kernel truly without CIFS
ini 'SERVER=192.168.0.9'
out="$(run_smb)"; rc=$?
contains "$out" "no CIFS" "reports a genuinely CIFS-less kernel"
check "$rc" "1" "exits 1 on a CIFS-less kernel"
drop_sandbox

# The case /proc/filesystems ALONE cannot answer: cifs is available as a module
# but nothing has loaded it, so it is not registered yet. A bare grep would be a
# false negative here -- and stricter than mount, which autoloads via
# get_fs_type() -> request_module("fs-cifs"). The modprobe stage is what covers
# it, and this is the case that proves the stage earns its place.
new_sandbox
printf 'nodev\tsysfs\n\text4\n' > "$SB/proc/filesystems"
cat > "$SB/bin/modprobe" <<STUB
#!/bin/sh
[ "\$1" = "cifs" ] || exit 1
printf 'nodev\tcifs\n' >> "$SB/proc/filesystems"
exit 0
STUB
chmod +x "$SB/bin/modprobe"
ini 'SERVER=192.168.0.9'
out="$(run_smb)"
lacks "$out" "no CIFS" "modular-but-unloaded cifs is NOT reported as unsupported"
contains "$out" "Done!" "modprobe stage loads it and the mount proceeds"
drop_sandbox

# --------------------------------------------------------------------------
echo
echo "ini is parsed as data"
new_sandbox
ini 'SERVER=192.168.0.9' \
    'USERNAME=mister' \
    'PASSWORD=p$a#s s"w' \
    '# a comment = not a key' \
    'PATH=/definitely/not' \
    'IFS=@'
out="$(run_smb)"
contains "$(cat "$SB/calls")" 'password=p$a#s s"w' "password with \$ # space and quote survives"
contains "$out" "Done!" "still ran (PATH was not hijacked)"
lacks "$(cat "$SB/calls")" "/definitely/not" "PATH= in the ini is ignored"
drop_sandbox

new_sandbox
ini 'SERVER=192.168.0.9' 'USERNAME=u' 'PASSWORD="  spaced  "'
run_smb >/dev/null
contains "$(cat "$SB/calls")" 'password=  spaced  ' "quoted value keeps inner spaces"
drop_sandbox

# cifs_mount.ini is read when mount_smb.ini is absent, so migrating costs
# nothing. Documented behaviour, worth pinning.
new_sandbox
printf 'SERVER=192.168.0.77\n' > "$SB/media/fat/Scripts/cifs_mount.ini"
run_smb >/dev/null
contains "$(cat "$SB/calls")" "//192.168.0.77/MiSTer" "falls back to cifs_mount.ini"
drop_sandbox

# --------------------------------------------------------------------------
echo
echo "boot entry"
new_sandbox
ini 'SERVER=192.168.0.9' 'MOUNT_AT_BOOT=true' 'BOOT_START_DELAY_SECONDS=0'
out="$(run_smb)"
US="$SB/media/fat/linux/user-startup.sh"
contains "$out" "Boot automount enabled" "reports enabling"
if [ -f "$US" ]; then ok "user-startup.sh created"; else bad "user-startup.sh created"; fi
if sh -n "$US" 2>/dev/null; then ok "user-startup.sh is valid POSIX sh"; else bad "user-startup.sh syntax"; fi

# The guard, tested by actually running user-startup.sh the way S99user does.
: > "$SB/calls"; : > "$SB/mounts"
( PATH="$SB/bin:$PATH"; sh "$US" stop >/dev/null 2>&1 )
sleep 1
check "$(wc -l < "$SB/calls" | tr -d ' ')" "0" "'stop' does not mount"
: > "$SB/calls"
( PATH="$SB/bin:$PATH"; sh "$US" start >/dev/null 2>&1 )
if wait_for_calls; then ok "'start' does mount"; else bad "'start' does mount"; fi

# Idempotent: enabling twice must not stack two blocks.
: > "$SB/mounts"
run_smb >/dev/null
check "$(grep -c 'BEGIN managed boot mount' "$US")" "1" "enabling twice leaves one block"

# And disabling removes it.
ini 'SERVER=192.168.0.9' 'MOUNT_AT_BOOT=false'
out="$(run_smb)"
contains "$out" "Boot automount disabled" "reports disabling"
check "$(grep -c 'managed boot mount' "$US")" "0" "block removed"
if sh -n "$US" 2>/dev/null; then ok "user-startup.sh still valid after removal"; else bad "syntax after removal"; fi
drop_sandbox

# A card migrating from cifs_mount.sh carries its boot entry. Both target the
# same mount points, so ours replaces it rather than racing it.
new_sandbox
US="$SB/media/fat/linux/user-startup.sh"
{
	printf '#!/bin/sh\n\necho "***" $1 "***"\n'
	printf '\n# cifs_mount: BEGIN managed boot mount\n'
	printf '[ -e "/media/fat/Scripts/cifs_mount.sh" ] && "/media/fat/Scripts/cifs_mount.sh" --boot-start &\n'
	printf '# cifs_mount: END managed boot mount\n'
} > "$US"
chmod +x "$US"
ini 'SERVER=192.168.0.9' 'MOUNT_AT_BOOT=true'
run_smb >/dev/null
lacks "$(cat "$US")" "cifs_mount" "legacy cifs_mount boot entry removed"
check "$(grep -c 'mount_smb.sh: BEGIN' "$US")" "1" "our block installed in its place"
contains "$(cat "$US")" 'echo "***"' "the user's own user-startup.sh content is preserved"
drop_sandbox

# --------------------------------------------------------------------------
echo
echo "failure reporting"
new_sandbox
ini 'SERVER=192.168.0.9'
out="$( MOUNT_SMB_TEST_FAIL=1 run_smb )"; rc=$?
# The subshell trap: if fail() is ever called via $(...) again, MOUNT_FAILURES
# stays 0, this prints "Done!" and exits 0 having mounted nothing.
contains "$out" "failure(s)" "a failed mount is counted"
check "$rc" "1" "exits 1 when a mount failed"
lacks "$out" "Done!" "does not claim success after failing"
drop_sandbox

# --------------------------------------------------------------------------
echo
echo "misc"
new_sandbox
out="$(run_smb --help)"; rc=$?
check "$rc" "0" "--help exits 0"
contains "$out" "mount_smb.ini" "--help names the ini"
out="$(run_smb)"; rc=$?
check "$rc" "1" "no SERVER exits 1"
contains "$out" "configure" "no SERVER explains what to do"
out="$(run_smb --nonsense)"; rc=$?
check "$rc" "2" "unknown option exits 2"
drop_sandbox

# Multiple directories over one connection: one CIFS mount, N bind mounts.
new_sandbox
ini 'SERVER=192.168.0.9' 'LOCAL_DIR=Amiga|C64|NES'
mkdir -p "$SB/tmp/mount_smb/Amiga" "$SB/tmp/mount_smb/C64" "$SB/tmp/mount_smb/NES"
run_smb >/dev/null
check "$(grep -c -- '-t cifs' "$SB/calls")" "1" "SINGLE_CONNECTION makes one CIFS mount"
check "$(grep -c -- '--bind' "$SB/calls")" "3" "and one bind mount per directory"
drop_sandbox

new_sandbox
ini 'SERVER=192.168.0.9' 'LOCAL_DIR=Amiga|C64' 'SINGLE_CONNECTION=false'
run_smb >/dev/null
check "$(grep -c -- '-t cifs' "$SB/calls")" "2" "SINGLE_CONNECTION=false mounts each directly"
drop_sandbox

# LOCAL_DIR="*" enumerates the share and skips MiSTer's own directories.
new_sandbox
ini 'SERVER=192.168.0.9' 'LOCAL_DIR=*'
mkdir -p "$SB/tmp/mount_smb/Amiga" "$SB/tmp/mount_smb/config" "$SB/tmp/mount_smb/linux"
run_smb >/dev/null
contains "$(cat "$SB/calls")" "mount_smb/Amiga" "'*' mounts a share directory"
lacks "$(cat "$SB/calls")" "mount_smb/config" "'*' skips config"
lacks "$(cat "$SB/calls")" "mount_smb/linux" "'*' skips linux"
drop_sandbox

# --umount tears down what was mounted, bind mounts before the connection.
new_sandbox
ini 'SERVER=192.168.0.9' 'LOCAL_DIR=Amiga|C64'
mkdir -p "$SB/tmp/mount_smb/Amiga" "$SB/tmp/mount_smb/C64"
run_smb >/dev/null
check "$(grep -c . "$SB/mounts")" "3" "three mounts present"
out="$(run_smb --umount)"
check "$(grep -c . "$SB/mounts")" "0" "--umount removes all of them"
contains "$out" "Done!" "--umount reports done"
drop_sandbox

# --------------------------------------------------------------------------
echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
