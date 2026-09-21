#!/usr/bin/env bash
#
# Unit test for the SD-card installer's first-boot splash
# (board/mister/de10nano/installer-overlay/init, ADR 0020 §6).
#
# WHY A SEPARATE TEST. The splash lives inside a PID-1 /init that can brick a
# board, and its only other coverage is scripts/test-sdcard-install.sh -- which
# needs a fully built sdcard.img and boots QEMU twice. That is far too slow and
# too heavy to catch an ordinary shell mistake. This test needs no build
# artifacts, no QEMU and no privilege: it extracts the splash section verbatim
# from /init, sources it under a POSIX shell against a STUBBED /proc/uptime and
# /sys/class/leds tree, and asserts the behaviour directly. It runs in about a
# second, so it can gate every PR.
#
# WHAT IT CANNOT TELL YOU. It exercises the splash in isolation, not the install
# flow that calls it. That the steps fire in the right order, against real
# hardware, with a real LED, is test-sdcard-install.sh's job and ultimately
# P5.4's. See ADR 0020 §6 for what the splash is and why it is a console UI plus
# one LED rather than the picture mr-fusion draws.
#
# Usage: scripts/test-installer-splash.sh [path/to/init]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
INIT="${1:-$ROOT/board/mister/de10nano/installer-overlay/init}"

# The shell the target actually runs is BusyBox ash. `dash` is the closest thing
# a CI runner ships and is the far stricter POSIX check of the two; fall back to
# `sh` so this still runs somewhere dash is absent.
SH="$(command -v dash || command -v sh)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log()  { printf '[test-splash] %s\n' "$*"; }
die()  { printf '[test-splash] FATAL: %s\n' "$*" >&2; exit 2; }

[ -f "$INIT" ] || die "no installer /init at $INIT"

log "init  = $INIT"
log "shell = $SH"

# ---------------------------------------------------------------- extraction
# The markers are a documented contract in /init itself -- see the comment on
# ">>> SPLASH SECTION BEGIN". Fail loudly rather than silently testing nothing if
# somebody renames or drops them.
sed -n '/^# >>> SPLASH SECTION BEGIN/,/^# >>> SPLASH SECTION END/p' "$INIT" > "$WORK/splash.sh"
[ -s "$WORK/splash.sh" ] || die "could not find the SPLASH SECTION markers in $INIT"
grep -q '^splash_init()'       "$WORK/splash.sh" || die "extracted section has no splash_init"
grep -q '^# >>> SPLASH SECTION END' "$WORK/splash.sh" || die "extraction ran past the END marker"
log "extracted $(wc -l < "$WORK/splash.sh") lines of splash section"

# ------------------------------------------------- SPLASH_TOTAL vs /init
# The one thing the sourced section below cannot check about itself: whether
# SPLASH_TOTAL still matches the steps /init actually calls. The header of that
# constant says "keep in sync with splash_step calls" and nothing enforced it,
# so a reorder that renumbers the steps -- which is exactly what ADR 0020 §8 did
# -- could leave the bar stalling at 90% or claiming 110%. Compare the declared
# total against the highest N in any `splash_step N` call outside the section
# (step 0 is splash_init's "starting up" and never the highest).
declared_total="$(sed -n 's/^SPLASH_TOTAL=\([0-9]*\).*/\1/p' "$INIT")"
[ -n "$declared_total" ] || die "no SPLASH_TOTAL= in $INIT"
highest_step="$(sed -n 's/^[[:space:]]*splash_step \([0-9]\{1,\}\) .*/\1/p' "$INIT" | sort -n | tail -1)"
[ -n "$highest_step" ] || die "no numbered splash_step calls in $INIT"
if [ "$declared_total" = "$highest_step" ]; then
	log "ok   SPLASH_TOTAL=$declared_total matches the highest splash_step call"
else
	die "SPLASH_TOTAL=$declared_total but the highest splash_step call is $highest_step -- renumbering left the progress bar lying"
fi

# ------------------------------------------------------------------- stubs
mkdir -p "$WORK/leds/hps_led0" "$WORK/run"
printf '0\n'           > "$WORK/leds/hps_led0/brightness"
printf 'mmc0\n'        > "$WORK/leds/hps_led0/trigger"
printf '12.34 56.78\n' > "$WORK/uptime"

# Retarget the three absolute paths at the stubs. Anchored on the exact strings
# the section uses; if /init ever stops using one of them this rewrite silently
# does nothing, so each is asserted below by behaviour, not by grep.
sed -i \
	-e "s#/proc/uptime#$WORK/uptime#g" \
	-e "s#/sys/class/leds#$WORK/leds#g" \
	-e "s#^SPLASH_FLAG=.*#SPLASH_FLAG=$WORK/run/splash.run#" \
	"$WORK/splash.sh"

# ------------------------------------------------------------------ the test
# Written as a script run BY $SH (not sourced by bash) so the splash section is
# parsed by a POSIX shell, which is the whole point.
cat > "$WORK/run-test.sh" <<'TEST_EOF'
set -u
W="$1"
# shellcheck source=/dev/null
. "$W/splash.sh"

led()     { cat "$W/leds/hps_led0/brightness"; }
trigger() { cat "$W/leds/hps_led0/trigger"; }

fail=0
ck() { # ck DESC GOT WANT
	if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
	else printf '  FAIL %s (got "%s", want "%s")\n' "$1" "$2" "$3"; fail=1; fi
}

# --- banner + init ---------------------------------------------------------
splash_init > "$W/banner.txt" 2>&1
ck "banner names the installer" \
	"$(grep -c 'F I R S T - B O O T   S E T U P' "$W/banner.txt")" "1"
ck "banner warns against pulling power" \
	"$(grep -c 'Do NOT power off' "$W/banner.txt")" "1"
ck "LED taken off its DTS mmc0 trigger" "$(trigger)" "none"
ck "LED starts dark"                    "$(led)"     "0"
ck "found the hps LED"                  "${splash_led##*/}" "hps_led0"
ck "non-tty stdout disables animation"  "$splash_tty" "0"

# --- steps -----------------------------------------------------------------
# The expected numbers are derived from SPLASH_TOTAL rather than hardcoded: the
# step count changed once already (9 -> 10, with the recoverable reorder of
# ADR 0020 §8) and hardcoding it made every one of these a two-line edit for no
# added coverage. What IS asserted literally is the arithmetic itself -- integer
# truncation of the bar fill, and a full bar exactly at the last step.
splash_step 1 "checking the card"   >/dev/null
ck "step 1 percentage" "$splash_pct" "$(( 100 / SPLASH_TOTAL ))"
splash_step 5 "writing the bootloader"  >/dev/null
ck "step 5 percentage" "$splash_pct" "$(( 5 * 100 / SPLASH_TOTAL ))"
ck "step 5 bar fill"   "${#splash_bar}" "$SPLASH_BAR_CELLS"
ck "step 5 bar is part-filled" \
	"$(printf '%s' "$splash_bar" | tr -dc '#' | wc -c | tr -d ' ')" \
	"$(( 5 * SPLASH_BAR_CELLS / SPLASH_TOTAL ))"
splash_step "$SPLASH_TOTAL" "finishing the install" >/dev/null
ck "last step percentage" "$splash_pct" "100"
ck "last step bar is full" "$splash_bar" "############################"
ck "bar is always exactly SPLASH_BAR_CELLS wide" "${#splash_bar}" "$SPLASH_BAR_CELLS"

# A non-tty must emit one plain line per step, so captured logs stay readable.
splash_step 4 "repartitioning the card" > "$W/step.txt"
ck "non-tty step prints a plain line" \
	"$(cat "$W/step.txt")" "[installer] step 4/$SPLASH_TOTAL: repartitioning the card"
ck "non-tty step emits no carriage return" \
	"$(tr -dc '\r' < "$W/step.txt" | wc -c | tr -d ' ')" "0"

# --- the elapsed clock -----------------------------------------------------
printf '75.99 1.0\n' > "$W/uptime"
ck "elapsed formats as mMMs" "$(splash_elapsed)" "1m03s"
printf '5.00 1.0\n' > "$W/uptime"
ck "clock going backwards clamps to zero" "$(splash_elapsed)" "0m00s"
printf 'garbage\n' > "$W/uptime"
ck "unparseable uptime does not crash"    "$(splash_elapsed)" "0m00s"
printf '12.34 56.78\n' > "$W/uptime"

# --- spinner ---------------------------------------------------------------
splash_frame=0; ck "spinner frame 0" "$(splash_spin_char)" '|'
splash_frame=1; ck "spinner frame 1" "$(splash_spin_char)" '/'
splash_frame=2; ck "spinner frame 2" "$(splash_spin_char)" '-'
splash_frame=3; ck "spinner frame 3" "$(splash_spin_char)" '\'
splash_frame=4; ck "spinner wraps"   "$(splash_spin_char)" '|'

# --- heartbeat child lifecycle --------------------------------------------
# The load-bearing one: this child is stopped by TRUNCATING a flag file and
# reaped with `wait`, because the installer BusyBox has neither kill nor rm.
# If this regresses, the installer hangs forever mid-reformat.
splash_pulse_start >/dev/null 2>&1
ck "pulse marks itself running"  "$splash_pulsing" "1"
ck "flag file is non-empty"      "$([ -s "$W/run/splash.run" ] && echo yes || echo no)" "yes"
sleep 2
splash_pulse_stop >/dev/null 2>&1
ck "pulse marks itself stopped"  "$splash_pulsing" "0"
ck "flag file was truncated"     "$([ -s "$W/run/splash.run" ] && echo yes || echo no)" "no"
ck "heartbeat child was reaped"  "$(jobs -p 2>/dev/null | wc -l | tr -d ' ')" "0"
# Solid-on is reserved for "stopped, wants a human"; a healthy install must never
# park the LED lit between two long phases.
ck "pulse parks the LED dark, not lit" "$(led)" "0"

splash_pulse_start >/dev/null 2>&1; splash_pulse_start >/dev/null 2>&1
splash_pulse_stop  >/dev/null 2>&1; splash_pulse_stop  >/dev/null 2>&1
ck "double start / double stop are idempotent" "$splash_pulsing" "0"

# --- terminal states -------------------------------------------------------
splash_fail >/dev/null 2>&1
ck "failure leaves the LED solid on"   "$(led)" "1"
splash_halt_ok >/dev/null 2>&1
ck "benign halt leaves the LED solid on" "$(led)" "1"
splash_done > "$W/done.txt" 2>&1
ck "completion banner drew" "$(grep -c 'INSTALL COMPLETE' "$W/done.txt")" "1"
ck "completion bar reads 100%" "$(grep -c '] 100%' "$W/done.txt")" "1"
ck "handing off puts the LED out" "$(led)" "0"

# --- degradation: a board with no such LED --------------------------------
# QEMU and any non-DE10-Nano host have no hps_led0. A splash must NEVER be able
# to fail an install, so every one of these must be a silent no-op.
splash_led=""
splash_led_set 1
splash_led_toggle
splash_tick   >/dev/null 2>&1
splash_step 2 "reading the payload" >/dev/null 2>&1
splash_done   >/dev/null 2>&1
printf '  ok   no-LED board: every LED path degraded to a no-op\n'

exit "$fail"
TEST_EOF

set +e
"$SH" "$WORK/run-test.sh" "$WORK"
rc=$?
set -e

echo
if [ "$rc" -eq 0 ]; then
	log "ALL CHECKS PASSED"
else
	log "one or more checks FAILED (see above)"
fi
exit "$rc"
