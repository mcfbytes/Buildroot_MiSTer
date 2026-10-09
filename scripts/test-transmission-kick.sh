#!/usr/bin/env bash
#
# Sandboxed behaviour test for the 92-transmission-kick dhcpcd hook
# (docs/bittorrent.md §10). The hook's paths are rewritten into a sandbox,
# the init script is a stub that records its verbs, and the daemon is a real
# process so the hook's exe and start-time checks are exercised, not mocked.
# TM_TEST_SH picks the shell the hook is sourced into (ci-tests.sh also runs
# it under the target's BusyBox ash via qemu-arm).
#
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/92-transmission-kick"
[ -f "$SRC" ] || { echo "test-transmission-kick.sh: ERROR: $SRC not found" >&2; exit 2; }

read -r -a TEST_SH <<< "${TM_TEST_SH:-sh}"

SB="$(mktemp -d "${TMPDIR:-/tmp}/tm-kick-test.XXXXXX")"
trap 'pkill -P $$ -f "$SB/" 2>/dev/null; rm -rf "$SB"' EXIT

TM_INIT="$SB/S92transmission"
TM_PID="$SB/jail.pid"
TM_EXEC="$SB/transmission-daemon"
TM_SETTINGS="$SB/settings.json"
IGMP="$SB/igmp"
STAMPDIR="$SB/transmission-kick"
CALLS="$SB/init.calls"

# Real executables, so /proc/PID/exe names them; bash because it runs under any argv[0].
cp "$BASH" "$TM_EXEC"
cp "$BASH" "$SB/not-transmission"

cat > "$TM_INIT" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$CALLS"
EOF
chmod +x "$TM_INIT"

rewrite() {
	sed -e "s|/etc/init.d/S92transmission|$TM_INIT|g" \
	    -e "s|/run/transmission/jail.pid|$TM_PID|g" \
	    -e "s|/usr/bin/transmission-daemon|$TM_EXEC|g" \
	    -e "s|/media/fat/linux/transmission/jail/settings.json|$TM_SETTINGS|g" \
	    -e "s|/proc/net/igmp|$IGMP|g" \
	    -e "s|/run/transmission-kick|$STAMPDIR|g" \
	    "$SRC"
}
rewrite > "$SB/async"
rewrite | sed -E 's|^([[:space:]]*)\) &.*TM-KICK-BACKGROUND.*|\1)|' > "$SB/sync"
if grep -qE '^[[:space:]]*\) &' "$SB/sync" || ! grep -qE '^[[:space:]]*\)$' "$SB/sync"; then
	echo "test-transmission-kick.sh: ERROR: could not make a synchronous copy (TM-KICK-BACKGROUND moved?)" >&2
	exit 2
fi
grep -qE '^[[:space:]]*\) &' "$SB/async" || { echo "test-transmission-kick.sh: ERROR: the hook no longer backgrounds its body" >&2; exit 2; }

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; [ -s "$SB/out" ] && sed 's/^/          console: /' "$SB/out"; fail=$((fail + 1)); }
must()   { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
mustnt() { local d="$1"; shift; if "$@"; then bad "$d"; else ok "$d"; fi; }

starttime() { sed 's/^.*) //' "/proc/$1/stat" | cut -d' ' -f20; }
_daemon=""
_stop() { [ -n "$_daemon" ] && kill "$_daemon" 2>/dev/null; wait "$_daemon" 2>/dev/null; _daemon=""; }
# The trailing `:` keeps bash from exec()ing sleep, so the exe stays the copy.
_spawn() { _stop; "$1" -c 'sleep 60; :' </dev/null >/dev/null 2>&1 & _daemon=$!; sleep 0.1; }
tm_running()  { _spawn "$TM_EXEC"; printf '%s %s\n' "$_daemon" "$(starttime "$_daemon")" > "$TM_PID"; }
tm_impostor() { _spawn "$SB/not-transmission"; printf '%s %s\n' "$_daemon" "$(starttime "$_daemon")" > "$TM_PID"; }
tm_wrongtime() { _spawn "$TM_EXEC"; printf '%s %s\n' "$_daemon" 1 > "$TM_PID"; }
tm_stopped()  { _stop; rm -f "$TM_PID"; }
tm_stale()    { _stop; ( : ) & local p=$!; wait "$p"; printf '%s 1\n' "$p" > "$TM_PID"; }
tm_zero()     { _stop; printf '0 1\n' > "$TM_PID"; }

lpd_on()      { printf '{\n    "lpd-enabled": true,\n    "dht-enabled": true\n}\n' > "$TM_SETTINGS"; }
lpd_off()     { printf '{\n    "lpd-enabled": false\n}\n' > "$TM_SETTINGS"; }
not_joined()  { printf 'Idx\tDevice    : Count Querier\tGroup    Users Timer\tReporter\n2\teth0      :     1      V3\n\t\t\t\t010000E0     1 0:00000000\t\t0\n' > "$IGMP"; }
joined()      { not_joined; printf '\t\t\t\t8F98C0EF     1 0:00000000\t\t0\n' >> "$IGMP"; }
reboot_sim()  { rm -rf "$STAMPDIR"; rm -f "$CALLS"; }

# fire COPY REASON IF_UP -- one dhcpcd event, sourced the way dhcpcd-run-hooks does.
fire() {
	# shellcheck disable=SC2016 # $1 is the inner shell's, by design
	reason="$2" if_up="$3" "${TEST_SH[@]}" -c '. "$1"; echo still-in-dhcpcd-shell' sh "$SB/$1" > "$SB/out" 2>&1
}
kicked()  { [ -s "$CALLS" ] && [ "$(cat "$CALLS")" = restart ]; }
stamped() { [ -d "$STAMPDIR" ]; }
returned() { grep -qx still-in-dhcpcd-shell "$SB/out"; }

echo "test-transmission-kick.sh: shell = ${TEST_SH[*]}"

reboot_sim; tm_running; lpd_on; not_joined
fire sync BOUND true
must "BOUND, daemon running, LPD not joined: restarts it"   kicked
must "  ... and spends the stamp"                           stamped
must "  ... and returns to dhcpcd's shell"                  returned
must "  ... and says why on dhcpcd's console"               grep -q 'Local Peer Discovery' "$SB/out"
rm -f "$CALLS"; fire sync BOUND true
mustnt "a second BOUND in the same boot does not restart"   kicked

reboot_sim; fire sync REBOOT true
must "REBOOT (lease re-acquired) restarts too"              kicked

for r in RENEW REBIND BOUND6 REBOOT6 EXPIRE NOCARRIER PREINIT; do
	reboot_sim; fire sync "$r" true
	mustnt "$r: does not restart"                           kicked
done

reboot_sim; fire sync BOUND false
mustnt "if_up=false: does not restart"                      kicked
reboot_sim; fire sync BOUND 'true; touch '"$SB/pwned"
mustnt "if_up is data, never run"                           test -e "$SB/pwned"

reboot_sim; joined; fire sync BOUND true
mustnt "LPD already joined: does not restart"               kicked
mustnt "  ... and the stamp is not spent"                   stamped
not_joined

reboot_sim; lpd_off; fire sync BOUND true
mustnt "lpd-enabled false: does not restart"                kicked
lpd_on

for state in tm_stopped tm_stale tm_zero tm_impostor tm_wrongtime; do
	reboot_sim; "$state"; fire sync BOUND true
	mustnt "$state: does not restart"                       kicked
	mustnt "$state: the stamp is not spent"                 stamped
done
printf 'garbage\n' > "$TM_PID"; reboot_sim; fire sync BOUND true
mustnt "a garbage pidfile: does not restart"                kicked

reboot_sim; tm_running; rm -f "$TM_SETTINGS" "$IGMP"
fire sync BOUND true
must "no settings.json (defaults: LPD on) and no igmp file: restarts" kicked
lpd_on; not_joined

reboot_sim; tm_running
start=$(date +%s%N); fire async BOUND true; end=$(date +%s%N)
must "the real hook returns to dhcpcd's shell"              returned
for _ in $(seq 50); do kicked && break; sleep 0.1; done
must "the real hook restarts in the background"             kicked
must "  ... without holding dhcpcd for long"                test $(( (end - start) / 1000000 )) -lt 2000

_stop
echo "test-transmission-kick.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
