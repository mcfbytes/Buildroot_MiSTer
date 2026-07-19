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
# BOTH SERIES ARE LINTED
# ----------------------
# There are two patch directories, and the second one needs this check MORE than the
# first, not less:
#
#   <BR2_LINUX_KERNEL_PATCH>/            carried — applied by Buildroot to the shipped
#                                        image and replayed by the export;
#   <BR2_LINUX_KERNEL_PATCH>-upstream/   upstream-only — replayed by the export and by
#                                        nothing else. See scripts/export-kernel-tree.sh.
#
# A malformed `From:` in the carried series at least gets a patch that the image build
# touches daily. In the upstream-only series NOTHING else reads the file at all, so the
# only thing that ever exercises it is `git am` at export time — which is exactly the
# moment you least want to discover it, and which happens rarely enough that the defect
# can sit for months. So the default here is both directories, and CI runs it with no
# arguments.
#
# Usage: scripts/lint-kernel-patches.sh [patch-dir...]
#   With no arguments, lints the series named by BR2_LINUX_KERNEL_PATCH in
#   configs/mister_de10nano_defconfig, plus the upstream-only series alongside it
#   ("<that path>-upstream") when that directory exists.
#   A directory named on the command line must exist and contain patches.
#
# Exit: 0 = every patch is am-able; 1 = at least one is not (details on stderr).

set -o errexit
set -o nounset
set -o pipefail

# Assigned then marked readonly separately: `readonly X="$(cmd)"` masks cmd's exit status
# (shellcheck SC2155), and the rest of scripts/ avoids that pattern.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly DEFCONFIG="$REPO_ROOT/configs/mister_de10nano_defconfig"

# Resolve the default from the defconfig rather than hardcoding the path, which is what
# the usage text above has always promised and what scripts/export-kernel-tree.sh already
# does. Hardcoding it meant this script and the export could disagree about which series
# is the real one after a defconfig edit -- and the disagreement would show up as a green
# lint followed by a failed `git am`.
patch_dirs=("$@")
if ((${#patch_dirs[@]} == 0)); then
	# Same sed as export-kernel-tree.sh: deliberately NOT anchored on the closing quote,
	# because this defconfig carries trailing comments on some lines.
	default_dir="$(sed -n 's/^BR2_LINUX_KERNEL_PATCH="\([^"]*\)".*$/\1/p' "$DEFCONFIG" | tail -1)"
	default_dir="${default_dir//\$(BR2_EXTERNAL_MISTER_PATH)/$REPO_ROOT}"

	if [[ -z $default_dir ]]; then
		printf 'lint-kernel-patches: BR2_LINUX_KERNEL_PATCH not set in %s\n' "$DEFCONFIG" >&2
		exit 1
	fi

	patch_dirs=("$default_dir")

	# The upstream-only series is optional by design: this repo carried none of them for
	# most of its life, and an absent one legitimately means "there are none". So is an
	# EMPTY one -- the directory ships a README.md and a `not-in-image` file that exist
	# whether or not any patch does, and CI failing because the series is momentarily
	# empty would be a check that punishes the tidy state. An explicitly named directory
	# is held to the stricter rule below, matching scripts/export-kernel-tree.sh:
	# --upstream-patches on an empty directory is an error there too.
	shopt -s nullglob
	upstream_found=("${default_dir}-upstream"/*.patch)
	shopt -u nullglob
	if ((${#upstream_found[@]})); then
		patch_dirs+=("${default_dir}-upstream")
	elif [[ -d "${default_dir}-upstream" ]]; then
		printf 'note: %s holds no patches yet — nothing to lint there.\n' \
			"${default_dir}-upstream"
	fi
fi

for dir in "${patch_dirs[@]}"; do
	if [[ ! -d $dir ]]; then
		printf 'lint-kernel-patches: no such patch directory: %s\n' "$dir" >&2
		exit 1
	fi
done

# mailinfo writes the split message body and diff out as files; we only care about
# the identity summary it prints, so they go to a scratch dir we discard.
# Explicit template, matching scripts/ci-tests.sh and scripts/check-linux-img.sh: bare
# `mktemp -d` is a GNU extension and errors out on BSD/macOS mktemp, which wants one.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/lint-kernel-patches.XXXXXX")" ||
	exit 1
trap 'rm -rf "$scratch"' EXIT

checked=0
failed=0

for dir in "${patch_dirs[@]}"; do
	printf '=== %s\n' "$dir"
	in_dir=0

	for patch in "$dir"/*.patch; do
		[[ -e $patch ]] || continue
		name="$(basename "$patch")"
		checked=$((checked + 1))
		in_dir=$((in_dir + 1))

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

	# Per-directory, not just in aggregate. A directory that exists and holds no patches
	# is someone's half-finished work or a bad path, and rolling it into a global count
	# would let a populated series mask an empty one right next to it.
	if ((in_dir == 0)); then
		printf 'lint-kernel-patches: no *.patch files found in %s\n' "$dir" >&2
		exit 1
	fi
done

printf '\n'
if ((failed)); then
	printf 'RESULT: FAIL — %d of %d patch(es) are not `git am`-able.\n' "$failed" "$checked" >&2
	printf 'These build fine under Buildroot (`patch -p1` ignores mail headers) but\n' >&2
	printf 'cannot be replayed as git history. Fix the `From:` line to `Name <email>`.\n' >&2
	exit 1
fi

printf 'RESULT: PASS — all %d patches in %d series are `git am`-able.\n' \
	"$checked" "${#patch_dirs[@]}"
