#!/usr/bin/env bash
#
# Unit test for the one-time authorized_keys migration in
# board/mister/de10nano/rootfs-overlay/etc/init.d/S50sshd (issue #183).
#
# WHY A SEPARATE TEST. The function moves the user's SSH key from the
# pre-#183 location (/media/fat/linux/authorized_keys) to the standard one
# (/media/fat/config/authorized_keys) and then DELETES the old file. On a box
# whose root password nobody remembers, that file is the only way in -- so a
# bug here is not "the migration did not happen", it is "the key is gone".
# The rest of the SSH plumbing has coverage (scripts/ci-tests.sh asserts the
# shipped sshd_config, the rig proves key auth end to end), but neither of
# those ever runs this function. This does, in about a second, with no build
# artifacts, no QEMU and no privilege.
#
# WHY IT RUNS EVERYTHING TWICE. The target runs BusyBox applets, not GNU
# coreutils, and the two disagree on exactly the edge this function leans on:
#
#   grep -F -x -v -f <EMPTY pattern file> <input>
#     GNU grep     -> the empty pattern set matches nothing, every line passes
#     BusyBox grep -> the empty pattern set matches everything, no line passes
#
# A zero-byte /media/fat/config/authorized_keys (an easy thing for a user to
# leave behind) therefore took a GNU-clean merge and produced an EMPTY result
# under BusyBox -- which also silently satisfied a naive "is anything missing?"
# check, so the old file was deleted. Case 12 below is that bug. It cannot be
# reproduced with GNU grep, which is why the BusyBox pass is not optional
# garnish: it is the pass that matters.
#
# WHAT IT CANNOT TELL YOU. It exercises the function in isolation against a
# sandbox directory, not against exFAT, and not in the context of start(). That
# sshd then actually accepts a key from the migrated file is the rig's job
# (docs/ssh-ftp-parity.md §1.3).
#
# Usage: scripts/test-authorized-keys-migration.sh [path/to/S50sshd]
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
S50="${1:-$ROOT/board/mister/de10nano/rootfs-overlay/etc/init.d/S50sshd}"

# The shell the target runs for init scripts is bash (/bin/sh -> bash on this
# image, PR #145), but the function is written to POSIX sh; dash is the
# stricter check and is what CI runners ship. Fall back to sh.
SH="$(command -v dash || command -v sh)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '[test-authkeys] %s\n' "$*"; }
die() { printf '[test-authkeys] FATAL: %s\n' "$*" >&2; exit 2; }

[ -f "$S50" ] || die "no S50sshd at $S50"

log "script = $S50"
log "shell  = $SH"

# ---------------------------------------------------------------- extraction
# From the AUTHKEYS constants through the end of migrate_authorized_keys() --
# the first `}` in column 1 closes that function. Taking the constants too
# means the test uses the SHIPPED paths rather than a copy of them that could
# drift.
sed -n '/^AUTHKEYS=/,/^}/p' "$S50" > "$WORK/migrate.sh"
grep -q '^migrate_authorized_keys()' "$WORK/migrate.sh" || die "migrate_authorized_keys() not found in $S50"
grep -q '^}$'                        "$WORK/migrate.sh" || die "extraction did not reach the end of the function"
grep -q '^start()'                   "$WORK/migrate.sh" && die "extraction ran past the function into start()"
log "extracted $(wc -l < "$WORK/migrate.sh") lines"

# Retarget the three absolute paths at the sandbox. Each rewrite is asserted,
# so a rename in S50sshd fails the test loudly instead of quietly testing a
# function that still points at the real /media/fat.
rewrite() { # <sed-expr> <description>
	local before after
	before="$(md5sum < "$WORK/migrate.sh")"
	sed -i "$1" "$WORK/migrate.sh"
	after="$(md5sum < "$WORK/migrate.sh")"
	[ "$before" != "$after" ] || die "path rewrite matched nothing ($2) -- S50sshd changed shape"
}
rewrite "s#^AUTHKEYS=/media/fat/config/authorized_keys#AUTHKEYS=$WORK/card/config/authorized_keys#"      "AUTHKEYS"
rewrite "s#^AUTHKEYS_LEGACY=/media/fat/linux/authorized_keys#AUTHKEYS_LEGACY=$WORK/card/linux/authorized_keys#" "AUTHKEYS_LEGACY"
rewrite "s#/run/authorized_keys\.#$WORK/run/authorized_keys.#g"                                          "/run intermediates"

# ------------------------------------------------------------------- harness
K1='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1 one@pc'
K2='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB2 two@laptop'

L="$WORK/card/linux/authorized_keys"
C="$WORK/card/config/authorized_keys"

failures=0
pass_label=""
desc=""
out=""
rc=0

reset() {
	rm -rf "$WORK/card" "$WORK/run"
	mkdir -p "$WORK/card/linux" "$WORK/run"
}

# Each case runs the function in a fresh shell, so a stray variable cannot leak
# from one case into the next.
migrate() { "$SH" -c ". '$WORK/migrate.sh'; migrate_authorized_keys" 2>&1; }

# rc is captured, never fatal: a non-zero return is a RESULT here (case 8
# expects one), and `out=$(...)` under `set -e` would otherwise abort the run.
run() {
	out=""
	rc=0
	out="$(migrate)" || rc=$?
}

pass() { printf '  %-58s PASS\n' "$desc"; }
fail() {
	printf '  %-58s FAIL\n' "$desc"
	printf '    rc=%s out=%s\n' "$rc" "${out:-<none>}" >&2
	printf '    config: %s\n' "$(cat "$C" 2>&1 || true)" >&2
	printf '    legacy: %s\n' "$(cat "$L" 2>&1 || true)" >&2
	failures=$((failures + 1))
}

# Non-blank line count, which is what "how many keys landed" means here.
keycount() { grep -c . "$1" 2>/dev/null || true; }

# --------------------------------------------------------------------- cases
run_suite() {
	log "=== pass: $pass_label ==="

	desc="1  legacy only, config dir absent"
	reset; printf '%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] && [ "$(cat "$C")" = "$K1" ]
	then pass; else fail; fi

	desc="2  legacy only, config dir exists, no key file"
	reset; mkdir -p "$WORK/card/config"; printf '%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] && [ "$(cat "$C")" = "$K1" ]
	then pass; else fail; fi

	desc="3  both exist, different keys -> merged, nothing lost"
	reset; mkdir -p "$WORK/card/config"
	printf '%s\n' "$K2" > "$C"; printf '%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] &&
	   grep -qxF "$K1" "$C" && grep -qxF "$K2" "$C" && [ "$(keycount "$C")" = 2 ]
	then pass; else fail; fi

	desc="4  both exist, same key -> no duplicate"
	reset; mkdir -p "$WORK/card/config"
	printf '%s\n' "$K1" > "$C"; printf '%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] && [ "$(keycount "$C")" = 1 ]
	then pass; else fail; fi

	desc="5  legacy holds no keys -> retired, no config file created"
	reset; printf '# just a comment\n\n   \n' > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] && [ ! -e "$C" ]
	then pass; else fail; fi

	desc="6  no legacy file -> silent no-op"
	reset; mkdir -p "$WORK/card/config"; printf '%s\n' "$K1" > "$C"; run
	if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(cat "$C")" = "$K1" ]
	then pass; else fail; fi

	desc="7  comments carried over alongside keys"
	reset; printf '# my key\n%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] &&
	   grep -qxF "$K1" "$C" && grep -qxF '# my key' "$C"
	then pass; else fail; fi

	# A regular file where the config DIRECTORY should be: mkdir -p and the
	# copy both fail, which is the "migration impossible" branch. What matters
	# is that the user's key is still where sshd's -o fallback will look for
	# it, and that the console says so.
	desc="8  destination unusable -> rc=1, legacy KEPT, warns"
	reset; printf '%s\n' "$K1" > "$L"; : > "$WORK/card/config"; run
	if [ "$rc" -eq 1 ] && [ "$(cat "$L")" = "$K1" ] &&
	   printf '%s' "$out" | grep -q WARNING
	then pass; else fail; fi

	desc="9  idempotent: second boot is a silent no-op"
	reset; printf '%s\n' "$K1" > "$L"; migrate >/dev/null 2>&1 || true; run
	if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$(cat "$C")" = "$K1" ]
	then pass; else fail; fi

	desc="10 no card mounted at all -> silent no-op"
	reset; rm -rf "$WORK/card"; run
	if [ "$rc" -eq 0 ] && [ -z "$out" ]
	then pass; else fail; fi

	desc="11 no /run intermediates left behind"
	reset; printf '%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ -z "$(ls -A "$WORK/run" 2>/dev/null || true)" ]
	then pass; else fail; fi

	# THE ONE THAT ONLY FAILS UNDER BUSYBOX -- see the header. An empty
	# destination file must not swallow the key being migrated into it.
	desc="12 empty config file present -> legacy key still lands"
	reset; mkdir -p "$WORK/card/config"; : > "$C"; printf '%s\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] && grep -qxF "$K1" "$C"
	then pass; else fail; fi

	# Written from Windows with Notepad. The line keeps its CR either way --
	# the point is that it is not dropped, duplicated or mangled.
	desc="13 CRLF legacy file -> the line still arrives, once"
	reset; printf '%s\r\n' "$K1" > "$L"; run
	if [ "$rc" -eq 0 ] && [ ! -e "$L" ] && [ "$(keycount "$C")" = 1 ]
	then pass; else fail; fi

	desc="14 several legacy keys, one already present -> all arrive once"
	reset; mkdir -p "$WORK/card/config"
	printf '%s\n' "$K2" > "$C"; printf '%s\n%s\n' "$K1" "$K2" > "$L"; run
	if [ "$rc" -eq 0 ] && [ "$(keycount "$C")" = 2 ] &&
	   grep -qxF "$K1" "$C" && grep -qxF "$K2" "$C"
	then pass; else fail; fi
}

# ------------------------------------------------------- pass 1: host applets
pass_label="host ($(grep --version 2>/dev/null | head -1 || echo 'unknown grep'))"
run_suite

# ---------------------------------------------------- pass 2: BusyBox applets
# The applets the image actually ships, on the front of PATH, so the function's
# bare `grep`/`cp`/`mv`/... calls land on BusyBox without the function knowing.
# Each shim names its applet explicitly rather than relying on argv[0], so
# $BUSYBOX may be a wrapper as well as the binary itself -- which is how this
# pass can be pointed at the ARM BusyBox the image really ships:
#
#   printf '#!/bin/sh\nexec qemu-arm -L output/target output/target/usr/bin/busybox "$@"\n' > /tmp/bb
#   chmod +x /tmp/bb && BUSYBOX=/tmp/bb scripts/test-authorized-keys-migration.sh
BUSYBOX="${BUSYBOX:-$(command -v busybox || true)}"
if [ -n "$BUSYBOX" ]; then
	mkdir -p "$WORK/bb"
	for applet in grep cat cp mv rm mkdir wc sync ls; do
		printf '#!/bin/sh\nexec %s %s "$@"\n' "$BUSYBOX" "$applet" > "$WORK/bb/$applet"
		chmod +x "$WORK/bb/$applet"
	done

	# Assert the divergence this pass exists for, so that if a future BusyBox
	# ever adopts GNU's reading, this test says so out loud instead of just
	# going quietly green. (`sed -n 1p`, not `head -1`, throughout this
	# section: BusyBox prints a long applet list, and head closing the pipe
	# early turns into a SIGPIPE that `set -o pipefail` would treat as a
	# failure of the whole script.)
	: > "$WORK/empty-pattern"
	printf 'a-key-line\n' > "$WORK/one-line"
	if "$WORK/bb/grep" -F -x -v -f "$WORK/empty-pattern" "$WORK/one-line" >/dev/null 2>&1; then
		log "NOTE: this BusyBox treats an empty -f pattern file the GNU way"
		log "      (matches nothing), so case 12 is not BusyBox-specific here."
	else
		log "confirmed: BusyBox 'grep -f <empty>' matches every line (GNU: none)"
	fi

	pass_label="busybox ($("$BUSYBOX" 2>&1 | sed -n '1s/.*\(BusyBox v[0-9.]*\).*/\1/p' || true))"
	PATH="$WORK/bb:$PATH" run_suite
else
	log "SKIP: no busybox found -- the BusyBox pass did not run, and case 12"
	log "      cannot fail under GNU grep. Install busybox-static, or point"
	log "      \$BUSYBOX at one, to get it."
fi

echo
if [ "$failures" -eq 0 ]; then
	log "all cases passed"
	exit 0
fi
log "$failures case(s) FAILED"
exit 1
