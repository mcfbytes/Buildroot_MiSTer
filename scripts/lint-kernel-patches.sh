#!/usr/bin/env bash
#
# lint-kernel-patches.sh — assert the carried kernel patches are `git am`-able.
#
# WHY THIS EXISTS
# ---------------
# Buildroot applies these patches with `patch -p1` (support/scripts/apply-patches.sh),
# which reads only the diff hunks and ignores the mail headers entirely. So a patch
# can carry a malformed `From:` line, build a perfectly good kernel, and ship — the
# defect is invisible to every other check in this repo.
#
# It stops being invisible the moment the series is replayed as git history, which is
# what any export to a Linux-Kernel_MiSTer-style tree does (`git am`). `git am` needs
# a parseable author identity to write a commit and hard-fails without one:
#
#     fatal: empty ident name (for <>) not allowed
#
# That is a real bug we shipped: 0013-hid-flydigi-vader.patch carried
# `From: Alexey Melnikov` with no <email>, and `git am` of the series died on it.
#
# So the mail headers are an interface — one the primary build does not exercise.
# This script exercises it.
#
# HOW
# ---
# `git mailinfo` IS the parser `git am` uses to split a patch into identity + message
# + diff. Running it is therefore a real test of am-ability rather than a regex that
# approximates one, and it needs no kernel tree and no network — it is fast enough to
# run before the build rather than after it.
#
# A patch that fails to parse yields an empty Author/Email, which is exactly the
# condition that kills `git am`.
#
# Usage: scripts/lint-kernel-patches.sh [patch-dir]
#   patch-dir defaults to the series named by BR2_LINUX_KERNEL_PATCH in
#   configs/mister_de10nano_defconfig.
#
# Exit: 0 = every patch is am-able; 1 = at least one is not (details on stderr).

set -o errexit
set -o nounset
set -o pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly PATCH_DIR="${1:-$REPO_ROOT/board/mister/de10nano/linux-patches}"

if [[ ! -d $PATCH_DIR ]]; then
	printf 'lint-kernel-patches: no such patch directory: %s\n' "$PATCH_DIR" >&2
	exit 1
fi

# mailinfo writes the split message body and diff out as files; we only care about
# the identity summary it prints, so they go to a scratch dir we discard.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

checked=0
failed=0

for patch in "$PATCH_DIR"/*.patch; do
	[[ -e $patch ]] || continue
	name="$(basename "$patch")"
	checked=$((checked + 1))

	# `git mailinfo <msg> <patch>` reads the mail on stdin and prints Author/Email/
	# Subject/Date. It exits 0 even when it cannot parse an identity, so the empty
	# field — not the exit code — is the signal.
	if ! info="$(git mailinfo "$scratch/msg" "$scratch/patch" <"$patch" 2>"$scratch/err")"; then
		printf 'FAIL %s\n     git mailinfo could not parse this patch:\n' "$name" >&2
		sed 's/^/       /' "$scratch/err" >&2
		failed=$((failed + 1))
		continue
	fi

	author="$(sed -n 's/^Author: //p' <<<"$info")"
	email="$(sed -n 's/^Email: //p' <<<"$info")"
	subject="$(sed -n 's/^Subject: //p' <<<"$info")"

	problems=()
	[[ -n $author ]] || problems+=('no author name — `From:` needs `Name <email>`')
	[[ -n $email ]] || problems+=('no author email — `From:` needs `Name <email>`')
	[[ -n $subject ]] || problems+=('no subject — `Subject:` is the commit message')

	if ((${#problems[@]})); then
		printf 'FAIL %s\n' "$name" >&2
		printf '     %s\n' "${problems[@]}" >&2
		printf '     got: %s\n' "$(grep -m1 '^From:' "$patch" || echo '(no From: line at all)')" >&2
		failed=$((failed + 1))
	else
		printf 'ok   %-52s %s <%s>\n' "$name" "$author" "$email"
	fi
done

if ((checked == 0)); then
	printf 'lint-kernel-patches: no *.patch files found in %s\n' "$PATCH_DIR" >&2
	exit 1
fi

printf '\n'
if ((failed)); then
	printf 'RESULT: FAIL — %d of %d patch(es) are not `git am`-able.\n' "$failed" "$checked" >&2
	printf 'These build fine under Buildroot (`patch -p1` ignores mail headers) but\n' >&2
	printf 'cannot be replayed as git history. Fix the `From:` line to `Name <email>`.\n' >&2
	exit 1
fi

printf 'RESULT: PASS — all %d patches are `git am`-able.\n' "$checked"
