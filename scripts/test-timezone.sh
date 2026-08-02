#!/usr/bin/env bash
#
# scripts/test-timezone.sh — sandboxed functional test of the timezone
# autodetect dhcpcd hook
# (board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/90-timezone).
#
# WHY THIS EXISTS. The hook takes a string off the *network* and turns it into a
# filesystem path. That is the one piece of this image that does so, so its
# input validation is worth a real test rather than an eyeball. It also has a
# "happens exactly once, ever" contract (see the hook's own header) whose whole
# point is invisible in a single run -- you only see it break on the second
# connection. And it is *sourced into dhcpcd's shell*, so "leaks nothing" and
# "never exits its caller" are correctness properties too, not style. None of
# that is visible to the rootfs.tar checks in ci-tests.sh, which can only see
# that the file shipped.
#
# HOW. The hook is copied into a throwaway sandbox with its four absolute paths
# (/media/fat, /usr/share/zoneinfo/posix, /usr/bin/curl, /run/timezone-autodetect)
# rewritten to point inside it, and `curl` is stubbed with a script that answers
# whatever the case under test wants and records every call. The hook calls curl
# by absolute path, so that rewrite -- not a PATH shim -- is what the cases
# actually exercise; PATH is set as well only so the stub wins if that ever
# changes. Nothing here needs a build, a board, or a network: the zoneinfo files
# are synthesized (the hook only ever copies them, never parses them), so this
# runs anywhere in about a second.
#
# Each case sources the hook exactly as dhcpcd does, with $reason and $if_up in
# the environment. One sandbox copy has its `) &` rewritten to `)` so the body
# runs in the FOREGROUND and every assertion is deterministic instead of racing
# a background job; the unmodified copy is used for the two properties that only
# exist because of the backgrounding.
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

# shellcheck disable=SC2030,SC2031
# Subshell-scoped environment is the whole mechanism here, not an accident: each
# case sources the hook inside ( ) with its own $reason/$if_up/$PATH, exactly as
# dhcpcd-run-hooks does, so nothing carries between cases.

set -u
# Deliberately not -e: run every case, report the whole picture -- same
# rationale as ci-tests.sh and test-initramfs.sh.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SRC="$ROOT/board/mister/de10nano/rootfs-overlay/usr/lib/dhcpcd/dhcpcd-hooks/90-timezone"

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
LOCKDIR="$SB/lock"

mkdir -p "$ZONEDIR/America" "$FATDIR" "$SB/bin"
# Synthetic zoneinfo: the script copies these bytes, it never reads them, so
# distinctive filler is both sufficient and clearer in a failure message than a
# real TZif blob would be.
printf 'zoneinfo-America/New_York\n' > "$ZONEDIR/America/New_York"
printf 'zoneinfo-UTC\n'              > "$ZONEDIR/UTC"
# A file OUTSIDE the zone dir, for the path-traversal case to aim at.
printf 'SECRET\n' > "$SB/passwd"


# Stub curl. Answers with $SB/answer, or fails like a real curl would when
# there is no network (exit 22 is curl's HTTP-error code; -f uses it). Logs
# every invocation so cases can assert on "was the network touched at all".
TZFILE_FOR_STUB="$TZFILE"
cat > "$SB/bin/curl" <<EOF
#!/bin/sh
TZFILE="$TZFILE_FOR_STUB"
echo "\$*" >> "$SB/curl.calls"
# Block until the test releases us, rather than for a fixed time: a
# fixed sleep outlives the test run and leaves an orphan behind.
while [ -f "$SB/stall" ]; do sleep 0.1; done
# Simulate the user running timezone.sh while the lookup is in flight.
[ -f "$SB/set-tz-midflight" ] && printf 'CHOSEN-MIDFLIGHT' > "$TZFILE"
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

# Copy the hook with its absolute paths pointed inside the sandbox, and its
# retry loop shortened so an offline case takes a moment rather than a minute.
# The TZ_TRIES/TZ_INTERVAL lines live inside the subshell, hence the leading
# whitespace in the patterns; indentation of the replacement does not matter.
rewrite() {
	sed -e "s|/media/fat|$SB/media/fat|g" \
	    -e "s|/usr/share/zoneinfo/posix|$ZONEDIR|g" \
	    -e "s|/usr/bin/curl|$SB/bin/curl|g" \
	    -e "s|/run/timezone-autodetect|$LOCKDIR|g" \
	    -e 's|^[[:space:]]*TZ_TRIES=.*|TZ_TRIES=2|' \
	    -e 's|^[[:space:]]*TZ_INTERVAL=.*|TZ_INTERVAL=1|' \
	    "$SRC"
}

# Two sandbox copies of the hook:
#   sync  — `) &` rewritten to `)`, so the body runs in the foreground and the
#           assertions are race-free
#   async — untouched, for the two properties that exist only because of the &
rewrite > "$SB/async"
rewrite | sed -E 's|^([[:space:]]*)\) &.*TZ-BACKGROUND.*|\1)|' > "$SB/sync"
if grep -qE '^[[:space:]]*\) &' "$SB/sync"; then
	echo "test-timezone.sh: ERROR: the sandbox copy is still asynchronous" >&2
	echo "  (did the TZ-BACKGROUND marker move or change?)" >&2
	exit 2
fi
if ! grep -qE '^[[:space:]]*\)$' "$SB/sync"; then
	echo "test-timezone.sh: ERROR: no subshell close found in the sandbox copy" >&2
	exit 2
fi
if ! grep -qE '^[[:space:]]*\) &' "$SB/async"; then
	echo "test-timezone.sh: ERROR: the hook no longer backgrounds its body" >&2
	exit 2
fi


pass=0; fail=0; skipped=0
ok()   { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
skip() { printf '  SKIP  %s -- %s\n' "$1" "$2"; skipped=$((skipped + 1)); }
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

# fire <answer> [reason] [if_up] -- one dhcpcd address event, sourced exactly
# the way dhcpcd-run-hooks sources it. Defaults to the event that matters:
# BOUND with the interface up. With if_up given as the literal string "unset",
# if_up is left undefined -- a case dhcpcd never produces but a sourced file
# must survive.
fire() {
	printf '%s' "$1" > "$SB/answer"
	rm -f "$SB/curl.calls"
	(
		export reason="${2:-BOUND}"
		# ${3-true}, not ${3:-true}: an EMPTY if_up is a case under test
		# and must not be silently promoted to "true".
		if [ $# -ge 3 ]; then
			case "$3" in
			unset) ;;
			*) export if_up="$3" ;;
			esac
		else
			export if_up=true
		fi
		PATH="$SB/bin:$PATH"
		# shellcheck source=/dev/null
		. "$SB/sync"
		# Reached only if the hook did not exit its caller -- which in a
		# sourced file would end dhcpcd's whole hook run, taking
		# 20-resolv.conf and 30-hostname with it.
		: > "$SB/returned-to-dhcpcd"
	) > "$SB/out" 2>&1
}

# One event with the UNMODIFIED hook: body backgrounded, as dhcpcd sees it.
fire_async() {
	printf '%s' "$1" > "$SB/answer"
	rm -f "$SB/curl.calls"
	(
		export reason=BOUND if_up=true
		PATH="$SB/bin:$PATH"
		# shellcheck source=/dev/null
		. "$SB/async"
	) > "$SB/out" 2>&1
}

boot() { rm -f "$SB/returned-to-dhcpcd"; fire "$@"; }
# Invoked indirectly, as `must`/`mustnt` arguments.
# shellcheck disable=SC2329
queried() { [ -f "$SB/curl.calls" ]; }
# shellcheck disable=SC2329
request() { sed -n "$1p" "$SB/curl.calls"; }
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
must   "said it will retry on the next connection" \
	grep -q "will retry on the next connection" "$SB/out"
boot "America/New_York"   # ...the user has since configured WiFi
must   "a later boot still gets its guess" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"

echo "== 3b. a captive portal does NOT spend it either =="
# HTTP 200 is not an answer. A hotel/airport portal and an ISP that serves a
# search page for NXDOMAIN both return 200 + HTML; spending the guess on that
# network strands the box on UTC for the life of the card.
reset; boot "<html>captive portal</html>"
mustnt "no stamp after a portal answered instead of a provider" test -e "$TZSTAMP"
boot "America/New_York"   # ...off that network now
must   "detects normally once past the portal" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"

echo "== 3c. ...but a real zone name we do not ship DOES spend it =="
# A provider replied in the right shape. Asking it again tomorrow will not
# produce a zone we suddenly have.
reset; boot "Mars/Olympus_Mons"
must   "stamped after a provider named a zone we do not ship" test -e "$TZSTAMP"
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
reset; boot "/etc/passwd"
mustnt "absolute path rejected" test -e "$TZFILE"
# The one that actually discriminates: "//UTC" joins to "$ZONEDIR//UTC", which
# DOES resolve, so without an explicit leading-slash rejection this is accepted
# and installed. Whether that is reachable depends entirely on how the path
# happens to be joined -- which is the reason to reject the shape outright
# rather than rely on the join.
reset; boot "//UTC"
mustnt "absolute path rejected even when it would resolve" test -e "$TZFILE"
reset; boot ""
mustnt "empty answer rejected" test -e "$TZFILE"

echo "== 6. a slashless but real zone is accepted =="
# ip-api answers "UTC" for some IPs. Taking it at its word beats timing out.
reset; boot "UTC"
must "UTC installed" cmp -s "$TZFILE" "$ZONEDIR/UTC"

echo "== 7. giving up is loud, and says how to fix it by hand =="
reset; boot "Mars/Olympus_Mons"
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
must "requests are size-bounded (--max-filesize)" \
	grep -q -- '--max-filesize' "$SB/curl.calls"

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
if [ "$(id -u)" -eq 0 ]; then
	# chmod 500 does not stop root, so this case would not merely fail --
	# the stamp assertion would pass for the wrong reason. Refuse to run it
	# rather than report a green that means nothing.
	skip "an unwritable card does not spend the guess" "running as root"
else
	reset; chmod 500 "$FATDIR"; boot "America/New_York"; chmod 700 "$FATDIR"
	must   "reported the unwritable destination" grep -q "cannot write" "$SB/out"
	mustnt "a later boot still gets its guess"   test -e "$TZSTAMP"
	mustnt "no .tmp file left behind"            test -e "$TZFILE.tmp"
fi


echo "== 11b. a timezone set WHILE the lookup runs is not clobbered =="
# start() checked $TZFILE up to a couple of minutes before detect() writes, and
# the box has just come online -- ample time for the user to run timezone.sh
# from the Scripts menu. The stub writes the file mid-request to reproduce that.
reset; : > "$SB/set-tz-midflight"; boot "America/New_York"; rm -f "$SB/set-tz-midflight"
must   "the user's mid-flight choice survives" grep -qx "CHOSEN-MIDFLIGHT" "$TZFILE"
mustnt "and no .tmp file is left behind"       test -e "$TZFILE.tmp"


echo "== 13. one lookup at a time =="
reset; mkdir "$LOCKDIR"; boot "America/New_York"; rmdir "$LOCKDIR"
mustnt "a lookup already in flight is not duplicated" queried
reset; boot "America/New_York"
mustnt "lock released when the lookup ends" test -d "$LOCKDIR"

echo "== 14. it fires on an address, and only then =="
reset; boot "America/New_York" BOUND true
must   "BOUND with the interface up does the lookup" queried
must   "  ... and returns to dhcpcd instead of exiting" test -e "$SB/returned-to-dhcpcd"
reset; boot "America/New_York" RENEW true
must   "RENEW does too (a cheap no-op once spent)" queried
reset; boot "America/New_York" BOUND6 true
must   "BOUND6 does (inert on this kernel, correct if IPv6 is enabled)" queried
reset; boot "America/New_York" BOUND false
mustnt "an interface that is not up does not" queried
# if_up is compared as data, not executed. Unset, empty or junk must all read as
# "not up" rather than as a command for the sourcing shell to run.
reset; boot "America/New_York" BOUND unset
mustnt "if_up unset reads as not-up" queried
reset; boot "America/New_York" BOUND ""
mustnt "if_up empty reads as not-up" queried
reset; boot "America/New_York" BOUND "$SB/bin/curl"
mustnt "a junk if_up is not executed" queried
must   "  ... and the hook still returned to dhcpcd" test -e "$SB/returned-to-dhcpcd"
reset; boot "America/New_York" PREINIT true
mustnt "PREINIT (no address yet) does not" queried
reset; boot "America/New_York" DEPARTED true
mustnt "DEPARTED does not" queried

echo "== 15. it never delays dhcpcd, and leaks nothing into its shell =="
# The two cases that run the UNMODIFIED hook. The stub blocks until released, so
# a foreground body could not return inside the 3 s budget -- dhcpcd waits on
# the hook run, so a blocking lookup would stall every lease event.
reset; : > "$SB/stall"
fire_async_timed() {
	printf 'America/New_York' > "$SB/answer"
	rm -f "$SB/curl.calls"
	# shellcheck disable=SC2016  # $1/$2 are the inner shell's, on purpose
	timeout 3 sh -c '
		export reason=BOUND if_up=true
		PATH="$1/bin:$PATH"
		. "$2"
	' _ "$SB" "$SB/async" >/dev/null 2>&1
}
must "the sourcing shell returns while the lookup is in flight" fire_async_timed

# Sourced into dhcpcd's own shell, so anything defined at top level would leak
# into it and into every hook after this one. The subshell is what prevents
# that, and this is the assertion that says so.
# In a FRESH shell, not a subshell of this one: the harness defines TZFILE,
# TZSTAMP, ZONEDIR and LOCKDIR itself, so a subshell could not tell its own
# variables from the hook's. They are plain assignments here, not exports, so a
# new `sh -c` does not inherit them.
# shellcheck disable=SC2016  # $1 is the inner shell's argument, on purpose
leaks="$(PATH="$SB/bin:$PATH" reason=BOUND if_up=true sh -c '
	. "$1"
	for v in TZFILE TZSTAMP ZONEDIR CURL LOCKDIR TZ_TRIES TZ_INTERVAL \
		answered tries zone url raw; do
		eval "[ -n \"\${$v+x}\" ]" && echo "variable $v"
	done
	command -v stamp >/dev/null 2>&1 && echo "function stamp"
	:
' _ "$SB/async")"
if [ -z "$leaks" ]; then
	ok "nothing leaks into the shell that sourced it"
else
	bad "leaked into dhcpcd's shell: $(echo "$leaks" | tr '\n' ' ')"
fi

# Release the stalled request and let the background job finish, rather than
# leaving it (and its sleep) running after this script exits and its sandbox is
# deleted. Doubles as proof that the backgrounded lookup does complete.
rm -f "$SB/stall"
for _ in $(seq 50); do
	[ -e "$TZFILE" ] && break
	sleep 0.1
done
must "the backgrounded lookup then completed on its own" \
	cmp -s "$TZFILE" "$ZONEDIR/America/New_York"

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
