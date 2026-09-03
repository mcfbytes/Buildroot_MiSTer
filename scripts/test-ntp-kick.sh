#!/usr/bin/env bash
#
# scripts/test-ntp-kick.sh — sandboxed functional test of the ntpd kick dhcpcd
# hook
# (board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/91-ntp-kick).
#
# WHY THIS EXISTS. The hook's whole contract is about WHEN it does nothing, and
# none of that is visible in a single successful run:
#
#   - it must fire at most ONCE per boot. dhcpcd re-fires RENEW every few hours
#     for the life of the session, and restarting ntpd each time would discard
#     its accumulated clock discipline. You only see that break on the second
#     event.
#   - it must NOT claim its once-per-boot stamp on a pass that bailed out. The
#     ordering case this was written around -- a wired box, where the hook fires
#     during S41dhcpcd, BEFORE S49ntp has started ntpd -- depends entirely on
#     that, and it is exactly the sort of thing a reordered guard breaks
#     silently.
#   - it must never start an ntpd that is not already running, so a by-hand or
#     /etc/default/ntpd disable stands.
#   - it is SOURCED into dhcpcd's shell, so "leaks nothing" and "never exits its
#     caller" are correctness properties, not style. An `exit` here would end
#     dhcpcd's whole hook run and take 20-resolv.conf and 30-hostname with it.
#
# ci-tests.sh's rootfs.tar checks can only see that the file shipped. This tests
# what it does.
#
# HOW. The hook is copied into a throwaway sandbox with its three absolute paths
# (/etc/init.d/S49ntp, /var/run/ntpd.pid, /run/ntp-kick) rewritten to point
# inside it, and the init script is stubbed with one that records every
# invocation. Liveness is real: the "running" cases use this harness's own PID,
# and the "dead" case uses a PID we reaped ourselves. Nothing here needs a build,
# a board, or a network.
#
# Each case sources the hook exactly as dhcpcd does, with $reason and $if_up in
# the environment. One sandbox copy has its `) &` rewritten to `)` so the body
# runs in the FOREGROUND and every assertion is deterministic instead of racing a
# background job; the unmodified copy is kept so the backgrounding itself is
# still asserted.
#
# Usage: scripts/test-ntp-kick.sh
#   Exit 0 iff every case passed. Wired into scripts/ci-tests.sh, which runs it
#   twice: once under the host shell, and once under the target's own BusyBox ash
#   via qemu-arm -- the shell that will actually run this on the box. The host's
#   /bin/sh is usually dash, a good POSIX proxy but not the same interpreter.
#
# Env:
#   NTP_TEST_SH  shell to run the script under (default: sh). May be a command
#                with arguments, e.g.
#                NTP_TEST_SH="qemu-arm -L output/target output/target/bin/busybox sh"

# shellcheck disable=SC2030,SC2031
# Subshell-scoped environment is the mechanism here, not an accident: each case
# sources the hook inside ( ) with its own $reason/$if_up, as dhcpcd-run-hooks
# does, so nothing carries between cases.

set -u
# Deliberately not -e: run every case, report the whole picture -- same
# rationale as ci-tests.sh, test-initramfs.sh and test-timezone.sh.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/91-ntp-kick"

if [ ! -f "$SRC" ]; then
	echo "test-ntp-kick.sh: ERROR: $SRC not found" >&2
	exit 2
fi

read -r -a TEST_SH <<< "${NTP_TEST_SH:-sh}"

SB="$(mktemp -d "${TMPDIR:-/tmp}/ntp-kick-test.XXXXXX")"
trap 'rm -rf "$SB"' EXIT

NTP_INIT="$SB/S49ntp"
NTPD_PID="$SB/ntpd.pid"
STAMPDIR="$SB/ntp-kick"
CALLS="$SB/init.calls"

# The stub stands in for /etc/init.d/S49ntp: record the verb, say nothing.
cat > "$NTP_INIT" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$CALLS"
EOF
chmod +x "$NTP_INIT"

rewrite() {
	sed -e "s|/etc/init.d/S49ntp|$NTP_INIT|g" \
	    -e "s|/var/run/ntpd.pid|$NTPD_PID|g" \
	    -e "s|/run/ntp-kick|$STAMPDIR|g" \
	    "$SRC"
}

# Two sandbox copies:
#   sync  — `) &` rewritten to `)`, so assertions are race-free
#   async — untouched, so the backgrounding itself stays asserted
rewrite > "$SB/async"
rewrite | sed -E 's|^([[:space:]]*)\) &.*NTP-KICK-BACKGROUND.*|\1)|' > "$SB/sync"
if grep -qE '^[[:space:]]*\) &' "$SB/sync"; then
	echo "test-ntp-kick.sh: ERROR: the sandbox copy is still asynchronous" >&2
	echo "  (did the NTP-KICK-BACKGROUND marker move or change?)" >&2
	exit 2
fi
if ! grep -qE '^[[:space:]]*\)$' "$SB/sync"; then
	echo "test-ntp-kick.sh: ERROR: no subshell close found in the sandbox copy" >&2
	exit 2
fi
if ! grep -qE '^[[:space:]]*\) &' "$SB/async"; then
	echo "test-ntp-kick.sh: ERROR: the hook no longer backgrounds its body" >&2
	exit 2
fi

pass=0; fail=0; skipped=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
skip() { printf '  SKIP  %s -- %s\n' "$1" "$2"; skipped=$((skipped + 1)); }
bad() {
	printf '  FAIL  %s\n' "$1"
	[ -s "$SB/out" ] && sed 's/^/          console: /' "$SB/out"
	fail=$((fail + 1))
}
must()   { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
mustnt() { local d="$1"; shift; if "$@"; then bad "$d"; else ok "$d"; fi; }

# A PID that is certainly gone: spawn, reap, then confirm. PID reuse would make
# this a false negative rather than a false pass, and it is checked, not assumed.
DEADPID="$( ( : ) & echo $! )"
wait 2>/dev/null

# reboot — a fresh boot: tmpfs stamp gone, no record of past calls.
reboot_sim() { rm -rf "$STAMPDIR"; rm -f "$CALLS"; }

# ntpd_running / ntpd_stopped / ntpd_stale — the three pidfile states.
ntpd_running() { printf '%s\n' "$$" > "$NTPD_PID"; }
ntpd_stopped() { rm -f "$NTPD_PID"; }
ntpd_stale()   { printf '%s\n' "$DEADPID" > "$NTPD_PID"; }

# fire [reason] [if_up] -- one dhcpcd address event, sourced the way
# dhcpcd-run-hooks sources it, INSIDE ${TEST_SH[@]}. Running it under the
# harness's own shell would make NTP_TEST_SH decorative and the "target BusyBox
# ash" CI leg a no-op that prints PASS.
#
# Pass the literal string "unset" as if_up to leave it undefined -- a state
# dhcpcd never produces but a sourced file must survive. An EMPTY if_up is a
# distinct case, hence ${2-true} rather than ${2:-true}.
#
# The inner shell touches its second argument after sourcing: reached only if
# the hook did not exit its caller.
fire() {
	# shellcheck disable=SC2016  # $1/$2 belong to the inner shell, on purpose
	_src='. "$1"; : > "$2"'
	if [ "${2-}" = unset ]; then
		env -u if_up reason="${1:-BOUND}" \
			"${TEST_SH[@]}" -c "$_src" _ \
			"$SB/sync" "$SB/returned-to-dhcpcd" > "$SB/out" 2>&1
	else
		env reason="${1:-BOUND}" if_up="${2-true}" \
			"${TEST_SH[@]}" -c "$_src" _ \
			"$SB/sync" "$SB/returned-to-dhcpcd" > "$SB/out" 2>&1
	fi
}

# Invoked indirectly, as `must`/`mustnt` arguments.
# shellcheck disable=SC2329
kicked()  { [ -s "$CALLS" ]; }
# shellcheck disable=SC2329
kicks()   { [ -f "$CALLS" ] && [ "$(wc -l < "$CALLS")" -eq "$1" ]; }
# shellcheck disable=SC2329
stamped() { [ -d "$STAMPDIR" ]; }

printf '\n--- the kick itself ---\n'
reboot_sim; ntpd_running
fire BOUND true
must   "BOUND with ntpd running kicks it"                 kicked
must   "the verb is restart"                              grep -qx 'restart' "$CALLS"
must   "the once-per-boot stamp is claimed"               stamped

printf '\n--- once per boot, not once per event ---\n'
fire RENEW true
must   "a later RENEW does not kick again"                kicks 1
fire BOUND true
must   "a later BOUND does not kick again"                kicks 1
reboot_sim; ntpd_running
fire BOUND true
must   "the stamp re-arms on the next boot (tmpfs)"       kicks 1

printf '\n--- ntpd that is not running is left alone ---\n'
reboot_sim; ntpd_stopped
fire BOUND true
mustnt "no pidfile: does not start ntpd"                  kicked
mustnt "no pidfile: the stamp is NOT spent"               stamped
reboot_sim; ntpd_stale
fire BOUND true
mustnt "stale pidfile (dead pid): does not kick"          kicked
mustnt "stale pidfile: the stamp is NOT spent"            stamped
reboot_sim; printf 'not-a-pid\n' > "$NTPD_PID"
fire BOUND true
mustnt "garbage pidfile: does not kick"                   kicked
mustnt "garbage pidfile: the stamp is NOT spent"          stamped
reboot_sim; : > "$NTPD_PID"
fire BOUND true
mustnt "empty pidfile: does not kick"                     kicked

# The ordering case the hook was written around: on a wired box this fires
# during S41dhcpcd, before S49ntp has started ntpd. The pass must bail out
# WITHOUT spending the stamp, so a genuinely late interface still gets its kick.
printf '\n--- the wired-box ordering case ---\n'
reboot_sim; ntpd_stopped
fire BOUND true
mustnt "fires before ntpd exists: no kick"                kicked
ntpd_running
fire BOUND true
must   "a later address event still gets its one kick"    kicked

printf '\n--- events that must do nothing ---\n'
reboot_sim; ntpd_running
fire BOUND false
mustnt "if_up=false does not kick"                        kicked
fire BOUND ''
mustnt "empty if_up does not kick"                        kicked
fire BOUND unset
mustnt "unset if_up does not kick"                        kicked
fire NOCARRIER true
mustnt "NOCARRIER does not kick"                          kicked
fire PREINIT true
mustnt "PREINIT does not kick"                            kicked
fire EXPIRE true
mustnt "EXPIRE does not kick"                             kicked
mustnt "none of the above spent the stamp"                stamped

printf '\n--- missing init script ---\n'
reboot_sim; ntpd_running; chmod -x "$NTP_INIT"
fire BOUND true
mustnt "non-executable S49ntp: does not kick"             kicked
mustnt "non-executable S49ntp: the stamp is NOT spent"    stamped
chmod +x "$NTP_INIT"

printf '\n--- properties it has because it is SOURCED ---\n'
reboot_sim; ntpd_running
rm -f "$SB/returned-to-dhcpcd"
fire BOUND true
must   "never exits its caller (20-resolv.conf still runs)" \
	test -f "$SB/returned-to-dhcpcd"
# Every variable the hook sets lives inside its subshell; dhcpcd's shell must
# come back clean. Checked in the shell under test, not this one.
# shellcheck disable=SC2016  # $v/$1 belong to the inner shell, on purpose
leak_check='. "$1"; for v in NTP_INIT NTPD_PID STAMPDIR ntpd_pid; do
	eval "val=\${$v-UNSET}"; [ "$val" = UNSET ] || { echo "LEAKED $v"; exit 1; }
done; exit 0'
reboot_sim; ntpd_running
if env reason=BOUND if_up=true "${TEST_SH[@]}" -c "$leak_check" _ "$SB/sync" \
	> "$SB/out" 2>&1; then
	ok "leaks no variables into dhcpcd's shell"
else
	bad "leaks no variables into dhcpcd's shell"
fi

printf '\n--- structural ---\n'
must   "the shipped hook has no shebang (it is sourced)" \
	test "$(head -c 2 "$SRC")" != '#!'
mustnt "the shipped hook is not executable"               test -x "$SRC"
must   "the shipped hook still backgrounds its body" \
	grep -qE '^[[:space:]]*\) &' "$SB/async"

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
