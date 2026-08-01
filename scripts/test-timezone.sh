#!/usr/bin/env bash
#
# scripts/test-timezone.sh — sandboxed functional test of the first-boot
# timezone autodetect init script
# (board/mister/de10nano/rootfs-overlay/etc/init.d/S48timezone).
#
# WHY THIS EXISTS. S48timezone takes a string off the *network* and turns it
# into a filesystem path. That is the one piece of this image that does so, so
# its input validation is worth a real test rather than an eyeball. It also has
# a "happens exactly once, ever" contract (see the script's own header) whose
# whole point is invisible in a single run -- you only see it break on the
# second boot. Both are cheap to assert here and impossible to assert from the
# rootfs.tar checks in ci-tests.sh, which can only see that the file shipped.
#
# HOW. The script is copied into a throwaway sandbox with its three absolute
# paths (/media/fat, /usr/share/zoneinfo/posix, /usr/bin/curl) rewritten to
# point inside it, and `curl` is stubbed with a script that answers whatever the
# case under test wants and records every call. The script calls curl by
# absolute path, so that rewrite -- not a PATH shim -- is what the cases
# actually exercise; PATH is set as well only so the stub wins if that ever
# changes. Nothing here needs a build, a
# board, or a network: the zoneinfo files are synthesized (the script only ever
# copies them, never parses them), so this runs anywhere in about a second.
#
# The sandbox copy is also rewritten to run detect() in the FOREGROUND, so every
# assertion is deterministic instead of racing a background job. The real
# script backgrounds it, and that property -- start must not block boot -- is
# what the last case tests, against an unmodified copy.
#
# Usage: scripts/test-timezone.sh
#   Exit 0 iff every case passed. Wired into scripts/ci-tests.sh's Timezone
#   section, which runs it twice: once under the host shell, and once under the
#   target's own BusyBox ash via qemu-arm (TZ_TEST_SH, below) -- the shell that
#   will actually run this on the box. The host's /bin/sh is usually dash, which
#   is a good POSIX proxy but is not the same interpreter.
#
# Env:
#   TZ_TEST_SH   shell to run the script under (default: sh). May be a command
#                with arguments, e.g.
#                TZ_TEST_SH="qemu-arm -L output/target output/target/bin/busybox sh"

set -u
# Deliberately not -e: run every case, report the whole picture -- same
# rationale as ci-tests.sh and test-initramfs.sh.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/board/mister/de10nano/rootfs-overlay/etc/init.d/S48timezone"

if [ ! -f "$SRC" ]; then
	echo "test-timezone.sh: ERROR: $SRC not found" >&2
	exit 2
fi

# The shell the sandbox copy runs under. Word-split on purpose: it is a command
# line, not a path (see TZ_TEST_SH in the header).
read -r -a TEST_SH <<< "${TZ_TEST_SH:-sh}"
if ! "${TEST_SH[@]}" -c ':' 2>/dev/null; then
	echo "test-timezone.sh: ERROR: TZ_TEST_SH ('${TZ_TEST_SH:-sh}') cannot run a script" >&2
	exit 2
fi

SB="$(mktemp -d "${TMPDIR:-/tmp}/mister-tztest.XXXXXX")"
trap 'rm -rf "$SB"' EXIT

ZONEDIR="$SB/usr/share/zoneinfo/posix"
FATDIR="$SB/media/fat/linux"
TZFILE="$FATDIR/timezone"
TZSTAMP="$FATDIR/timezone.autodetect"
ROUTE="$SB/proc-route"
LOCKDIR="$SB/lock"

mkdir -p "$ZONEDIR/America" "$FATDIR" "$SB/bin"
# Synthetic zoneinfo: the script copies these bytes, it never reads them, so
# distinctive filler is both sufficient and clearer in a failure message than a
# real TZif blob would be.
printf 'zoneinfo-America/New_York\n' > "$ZONEDIR/America/New_York"
printf 'zoneinfo-UTC\n'              > "$ZONEDIR/UTC"
# A file OUTSIDE the zone dir, for the path-traversal case to aim at.
printf 'SECRET\n' > "$SB/passwd"

# Stand-in /proc/net/route, in the kernel's format: header line, then one route
# per line with a hex destination. 00000000 is the default route the script
# gates on. route_up/route_down swap between "we have a network" and "we do not".
route_up() {
	printf 'Iface\tDestination\tGateway\tFlags\n' > "$ROUTE"
	printf 'eth0\t00000000\t0102A8C0\t0003\n'    >> "$ROUTE"
}
route_down() {
	printf 'Iface\tDestination\tGateway\tFlags\n' > "$ROUTE"
	printf 'eth0\t0002A8C0\t00000000\t0001\n'    >> "$ROUTE"
}
route_up

# Stub curl. Answers with $SB/answer, or fails like a real curl would when
# there is no network (exit 22 is curl's HTTP-error code; -f uses it). Logs
# every invocation so cases can assert on "was the network touched at all".
cat > "$SB/bin/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$SB/curl.calls"
[ -f "$SB/stall" ] && sleep 5
# \$SB/down-first makes ONLY the first provider fail, so the HTTPS fallback
# path can be exercised rather than merely asserted to exist.
if [ -f "$SB/down-first" ]; then
	case "\$*" in *ip-api.com*) exit 22 ;; esac
fi
ans="\$(cat "$SB/answer")"
[ "\$ans" = FAIL ] && exit 22
printf '%s\n' "\$ans"
EOF
chmod +x "$SB/bin/curl"

# Two sandbox copies of the script under test:
#   .sync — detect() in the foreground, so assertions are race-free
#   .async — untouched control flow, for the "must not block boot" case
rewrite() {
	sed -e "s|/media/fat|$SB/media/fat|g" \
	    -e "s|/usr/share/zoneinfo/posix|$ZONEDIR|g" \
	    -e "s|/usr/bin/curl|$SB/bin/curl|g" \
	    -e "s|/proc/net/route|$ROUTE|g" \
	    -e "s|/proc/net/ipv6_route|$SB/proc-ipv6route|g" \
	    -e "s|/run/timezone-autodetect|$LOCKDIR|g" \
	    -e "s|^TZ_TRIES=.*|TZ_TRIES=2|" \
	    -e "s|^TZ_INTERVAL=.*|TZ_INTERVAL=1|" \
	    "$SRC"
}
rewrite > "$SB/async"
# Match any detect* function name, and verify afterwards that nothing is left
# backgrounded: keying this on one exact name meant a later rename silently
# produced an "async sync copy" and raced every assertion.
rewrite | sed -E 's|^([[:space:]]*)(detect[a-z_]*) &$|\1\2|' > "$SB/sync"
chmod +x "$SB/async" "$SB/sync"
if grep -qE '^[[:space:]]*detect[a-z_]* &$' "$SB/sync"; then
	echo "test-timezone.sh: ERROR: the sandbox copy is still asynchronous" >&2
	echo "  (a backgrounded call in S48timezone this rewrite does not match?)" >&2
	exit 2
fi
if ! grep -qE '^[[:space:]]*detect[a-z_]*$' "$SB/sync"; then
	echo "test-timezone.sh: ERROR: no detect call found in the sandbox copy" >&2
	echo "  (did S48timezone stop calling detect() from start()?)" >&2
	exit 2
fi

# The dhcpcd hook, pointed at a stub init script that just records its calls --
# what matters is WHEN dhcpcd makes it fire, not what the init script then does.
HOOK_SRC="$ROOT/board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/90-timezone"
if [ ! -f "$HOOK_SRC" ]; then
	echo "test-timezone.sh: ERROR: $HOOK_SRC not found" >&2
	exit 2
fi
mkdir -p "$SB/etc/init.d"
cat > "$SB/etc/init.d/S48timezone" <<EOF
#!/bin/sh
echo "\$1" >> "$SB/hook.calls"
EOF
chmod +x "$SB/etc/init.d/S48timezone"
sed -e "s|/etc/init.d/S48timezone|$SB/etc/init.d/S48timezone|g" "$HOOK_SRC" > "$SB/90-timezone"

pass=0; fail=0
ok()  { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() {
	printf '  FAIL  %s\n' "$1"
	# The script's own console output is the first thing you want on a
	# failure, so print it rather than making every assertion carry it.
	[ -s "$SB/out" ] && sed 's/^/          console: /' "$SB/out"
	fail=$((fail + 1))
}

# must <what> <cmd...>    -- cmd must succeed
# mustnt <what> <cmd...>  -- cmd must fail
must()   { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
mustnt() { local d="$1"; shift; if "$@"; then bad "$d"; else ok "$d"; fi; }

reset() { rm -f "$TZFILE" "$TZSTAMP" "$TZFILE.tmp"; rmdir "$LOCKDIR" 2>/dev/null; }

# boot <answer> -- one boot of the box, with the providers answering <answer>.
boot() {
	printf '%s' "$1" > "$SB/answer"
	rm -f "$SB/curl.calls"
	PATH="$SB/bin:$PATH" "${TEST_SH[@]}" "$SB/sync" start > "$SB/out" 2>&1
}

verb()    { PATH="$SB/bin:$PATH" "${TEST_SH[@]}" "$SB/sync" "$1" >/dev/null 2>&1; }

# hook <reason> <if_up> -- one dhcpcd event, sourced the way dhcpcd sources it.
# The trailing marker proves the hook did not `exit`, which in a sourced hook
# would end dhcpcd's whole run and take 20-resolv.conf/30-hostname with it.
hook() {
	rm -f "$SB/hook.calls" "$SB/hook.reached-end"
	(
		# Exported, as dhcpcd itself passes them: the hook reads them,
		# this shell does not.
		export reason="$1" if_up="$2"
		# shellcheck source=/dev/null
		. "$SB/90-timezone"
		: > "$SB/hook.reached-end"
	) >/dev/null 2>&1
}
hook_fired() { [ -f "$SB/hook.calls" ]; }
queried() { [ -f "$SB/curl.calls" ]; }
request() { sed -n "$1p" "$SB/curl.calls"; }

echo "shell under test: ${TZ_TEST_SH:-sh}"
echo "== 1. detected zone is installed verbatim =="
reset; boot "America/New_York"
must   "copied the zoneinfo file byte-for-byte to the data partition" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"
must   "reported the detection on the console" \
	grep -q "detected America/New_York" "$SB/out"
must   "recorded the result in the timezone.autodetect stamp" \
	grep -qs "America/New_York" "$TZSTAMP"
mustnt "no .tmp file left behind" test -e "$TZFILE.tmp"

echo "== 2. a timezone that is already set is never overwritten =="
reset; printf 'CHOSEN-BY-THE-USER' > "$TZFILE"; boot "America/New_York"
must   "existing timezone untouched" grep -qx "CHOSEN-BY-THE-USER" "$TZFILE"
mustnt "did not touch the network" queried
# An EMPTY timezone file is a failed write, not a choice -- the -s test treats
# it as unset so a half-written card self-heals instead of being stuck on UTC.
reset; : > "$TZFILE"; boot "America/New_York"
must "an empty timezone file is treated as unset, not as a choice" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"

echo "== 3. never reaching a provider does NOT spend the guess =="
# The common MiSTer story: flash the card, boot it, THEN set up WiFi. That first
# boot must not burn the one guess, or the box is stuck on UTC forever.
reset; boot "FAIL"
mustnt "no stamp when no provider was ever reached" test -e "$TZSTAMP"
must   "said it will retry once there is a network" \
	grep -q "will retry when the network is up" "$SB/out"
boot "America/New_York"   # ...the user has since configured WiFi
must   "a later boot still gets its guess" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"

echo "== 3b. ...but an answer we cannot use DOES spend it =="
# Asking the same broken provider the same question tomorrow will not help.
reset; boot "<html>captive portal</html>"
must   "stamped after a provider answered with junk" test -e "$TZSTAMP"
boot "America/New_York"
mustnt "no second guess on the next boot" queried
mustnt "left the timezone unset" test -e "$TZFILE"

echo "== 4. a pre-created stamp opts out before anything is sent =="
reset; : > "$TZSTAMP"; boot "America/New_York"
mustnt "never queried" queried
mustnt "no timezone written" test -e "$TZFILE"

echo "== 5. hostile answers are rejected =="
reset; boot "../../../../passwd"
mustnt "path traversal rejected" test -e "$TZFILE"
reset; boot 'America/New_York; touch '"$SB"'/pwned'
mustnt "command injection rejected" test -e "$SB/pwned"
mustnt "  ... and nothing was installed" test -e "$TZFILE"
reset
# shellcheck disable=SC2016  # a literal $(...) is the point: it must NOT expand
boot '$(touch '"$SB"'/pwned2)'
mustnt "command substitution rejected" test -e "$SB/pwned2"
reset; boot "<html>captive portal</html>"
mustnt "captive-portal HTML rejected" test -e "$TZFILE"
reset; boot "America"
mustnt "directory name rejected" test -e "$TZFILE"
reset; boot "Mars/Olympus_Mons"
mustnt "zone we do not ship rejected" test -e "$TZFILE"
reset; boot ""
mustnt "empty answer rejected" test -e "$TZFILE"

echo "== 6. a slashless but real zone is accepted =="
# ip-api answers "UTC" for some IPs. Taking it at its word beats timing out.
reset; boot "UTC"
must "UTC installed" cmp -s "$TZFILE" "$ZONEDIR/UTC"

echo "== 7. giving up is loud, and says how to fix it by hand =="
reset; boot "<html>captive portal</html>"
must "said it is staying on UTC"         grep -q "staying on UTC" "$SB/out"
must "pointed at the timezone.sh script" grep -q "timezone.sh"    "$SB/out"
reset; boot "FAIL"
must "retried while offline (2 tries x 2 providers = 4 requests)" \
	test "$(wc -l < "$SB/curl.calls")" -eq 4

echo "== 8. both providers are tried, in order, HTTP first then HTTPS =="
must "first request is ip-api.com (what timezone.sh uses)" \
	grep -qF 'http://ip-api.com/line/?fields=timezone' <<< "$(request 1)"
must "second request is the HTTPS fallback" \
	grep -qF 'https://ipapi.co/timezone' <<< "$(request 2)"
must "requests are time-bounded (--max-time)" \
	grep -q -- '--max-time' "$SB/curl.calls"

# ...and the fallback must actually WORK, not just be reached: ip-api down,
# ipapi.co answering, is the exact shape of a network that eats plain HTTP.
reset; : > "$SB/down-first"; boot "America/New_York"; rm -f "$SB/down-first"
must   "falls back to HTTPS when the first provider is down" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"
must   "  ... on the first round, without burning the retry window" \
	test "$(wc -l < "$SB/curl.calls")" -eq 2

echo "== 9. no data partition, or no curl -> silent no-op =="
reset; mv "$FATDIR" "$FATDIR.away"; boot "America/New_York"; mv "$FATDIR.away" "$FATDIR"
mustnt "no-op without a data partition" queried
reset; chmod -x "$SB/bin/curl"; boot "America/New_York"; chmod +x "$SB/bin/curl"
mustnt "no-op without curl" test -e "$TZFILE"

echo "== 10. an unwritable card does not spend the guess =="
reset; chmod 500 "$FATDIR"; boot "America/New_York"; chmod 700 "$FATDIR"
must   "reported the unwritable destination" grep -q "cannot write" "$SB/out"
mustnt "a later boot still gets its guess"   test -e "$TZSTAMP"
mustnt "no .tmp file left behind"            test -e "$TZFILE.tmp"

echo "== 11. init verbs =="
: > "$SB/out"
must   "stop exits 0 (rcK must not fail at shutdown)" verb stop
mustnt "an unknown verb exits nonzero, with usage"    verb bogus


echo "== 12. no default route -> nothing is sent, nothing is spent =="
# This is the "does it slow down a box with no network" answer: start() returns
# before it backgrounds anything, so there is not even a process to be slow.
reset; route_down; boot "America/New_York"; route_up
mustnt "never queried without a route" queried
mustnt "no timezone written"           test -e "$TZFILE"
mustnt "guess not spent"               test -e "$TZSTAMP"
mustnt "nothing said on the console"   test -s "$SB/out"

echo "== 13. one lookup at a time =="
reset; mkdir "$LOCKDIR"; boot "America/New_York"; rmdir "$LOCKDIR"
mustnt "a lookup already in flight is not duplicated" queried
reset; boot "America/New_York"
mustnt "lock released when the lookup ends" test -d "$LOCKDIR"

echo "== 14. the dhcpcd hook fires on an address, and only then =="
hook BOUND true
must   "BOUND with the interface up calls the init script" hook_fired
must   "  ... with 'start'" grep -qx start "$SB/hook.calls"
must   "  ... and returns to dhcpcd instead of exiting" test -e "$SB/hook.reached-end"
hook RENEW true
must   "RENEW calls it too (cheap no-op once spent)" hook_fired
hook BOUND6 true
must   "BOUND6 calls it (IPv6-only networks)" hook_fired
hook BOUND false
mustnt "an interface that is not up does not" hook_fired
hook PREINIT true
mustnt "PREINIT (no address yet) does not" hook_fired
hook DEPARTED true
mustnt "DEPARTED does not" hook_fired

echo "== 15. start returns immediately -- boot is never blocked =="
# Last on purpose: the one case that runs the UNMODIFIED script, so it leaves a
# real background job behind that anything after it would race.
# detect() must be backgrounded.
# The stub stalls 5s per request, so a foreground detect() could not return
# inside the 3s budget.
reset; : > "$SB/stall"; : > "$SB/out"
printf 'America/New_York' > "$SB/answer"
start_async() { PATH="$SB/bin:$PATH" timeout 3 "${TEST_SH[@]}" "$SB/async" start >/dev/null 2>&1; }
must "start returned while the lookup was still in flight" start_async
rm -f "$SB/stall"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
