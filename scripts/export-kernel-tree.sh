#!/usr/bin/env bash
#
# export-kernel-tree.sh — render the carried kernel series as a Linux-Kernel_MiSTer-style
# git tree: a pristine upstream tarball as one base commit, then one commit per patch.
#
# WHY
# ---
# This repo keeps the MiSTer kernel as {pinned upstream version + hash} + an ordered
# patch series. MiSTer-devel/Linux-Kernel_MiSTer keeps it as a materialized git tree:
# a squashed tarball commit (`v5.15.1`) with MiSTer commits replayed on top. Those are
# the SAME MODEL — tarball base plus ordered series — differing only in whether the
# base is stored as a hash or as 283MB of blobs. This script renders one into the other.
#
# It exists so the rendered tree is a BUILD OUTPUT, not a second source of truth. Edits
# belong in the patch series; this regenerates from it. Given the same inputs it emits
# byte-identical commits (see DETERMINISM), so re-running after no change is a no-op
# rather than a force-push of fresh SHAs.
#
# TWO SERIES: WHAT WE SHIP vs WHAT THIS TREE CARRIES
# --------------------------------------------------
# For most of this script's life those were the same set, and EXPORT.md said so: the
# exported tree WAS the shipped kernel, patch for patch. That is no longer true, and the
# difference is deliberate rather than drift.
#
# Linux-Kernel_MiSTer is upstream's kernel for every MiSTer, not just ours. Some of what
# it must carry, our image specifically does not want. The motivating case is the fork's
# `loop=` boot parameter (fork commit 3d95de58f, "Support for init loop device."), which
# patches init/do_mounts.c so the KERNEL itself mounts /media/fat and loop-mounts
# linux/linux.img as the root filesystem. That is upstream's boot mechanism — every stock
# MiSTer boots through it, and a 6.18 branch that dropped it would not boot on any of
# them. Our image replaced it with a real initramfs /init, so applying it here would add
# an unreachable second boot path to the kernel we ship (recorded as carried-upstream-only
# in docs/kernel-recon/reconciliation.md — carried for this tree, not for our image).
#
# Deleting it from the export to keep the two trees identical would be the wrong trade:
# it would break upstream's boot to preserve a documentation claim. Applying it to our
# image would be the other wrong trade. So there are two series:
#
#   board/mister/de10nano/linux-patches/            carried — applied by BOTH Buildroot
#                                                   (BR2_LINUX_KERNEL_PATCH) and this
#                                                   script. The kernel we ship.
#   board/mister/de10nano/linux-patches-upstream/   upstream-only — applied ONLY here.
#                                                   Buildroot never sees this directory.
#
# The second directory's path is DERIVED from the first ("${patch_dir}-upstream"), so a
# defconfig change moves both together and this script needs no edit. Numbering there
# starts at 0100 so a filename alone says which namespace it is in.
#
# The cost of the split is that EXPORT.md can no longer say "this tree is the shipped
# kernel". It must say what it now is: the shipped kernel PLUS exactly these N patches,
# each named, each with the reason it is not in our image. That is generated below from
# the files actually present — never hardcoded — and the export FAILS CLOSED if a patch
# in that directory has no stated reason, because a table row with a blank reason is
# worse than no table: it reads as reviewed when nothing reviewed it.
#
# WHAT YOU GET
# ------------
#   <output>/  a fresh git repo, branch MiSTer-v<major.minor>, containing:
#     - one base commit  "Linux <ver>"  — pristine upstream, hash-verified
#     - one commit per carried patch, original authorship preserved
#     - one commit per upstream-only patch, likewise (see TWO SERIES above)
#     - arch/arm/configs/MiSTer_defconfig — so the tree builds standalone:
#           make ARCH=arm MiSTer_defconfig && make ARCH=arm zImage
#       which is the thing `make linux` inside Buildroot cannot hand someone.
#     - EXPORT.md — states it is generated, names the source of truth, and records
#       the fork commit we last reconciled against.
#     - tag mister-<ver>
#
# WHERE THE BRANCH HANGS (--parent-repo/--parent)
# -----------------------------------------------
# Linux-Kernel_MiSTer is not one chain. Its tarball commits form a SPINE —
#
#   e12ed6c19 v5.13.12 -> 137491a75 v5.14 -> b6f2ca1c4 v5.14.5 -> aba1ef4c1 v5.15.1
#                                                                      |
#                                                              d9ac12a69 v6.18.38
#
# — and each MiSTer-vX.Y branch hangs off a spine point with the MiSTer series replayed
# on top (MiSTer-v5.15 = aba1ef4c1 + 112 commits). Every spine commit is a PRISTINE
# tarball with no MiSTer code in it, INCLUDING the newest one: upstream's own
# MiSTer-v6.18 work starts from d9ac12a69 "v6.18.38", a pristine 6.18.38 tarball commit
# whose parent is aba1ef4c1. A spine point is therefore not necessarily a leaf, and
# --parent must accept one that already has a branch hanging off it.
#
# So the right shape for a new kernel is to extend the spine the same way, parenting the
# base commit on the NEWEST spine point rather than on a branch tip. For 6.18 that means
# --parent d9ac12a691ead295c8bc6438754767b94c0f26a2, not aba1ef4c1:
#
#   aba1ef4c1 v5.15.1 --+-- [112 MiSTer commits] --> MiSTer-v5.15   (theirs, untouched)
#                       |
#                       +-- d9ac12a69 v6.18.38 --+-- [his commits] -> MiSTer-v6.18 (theirs)
#                                                |
#                                                +-- v6.18.50 -- [our commits] -> ours
#
# That buys three things at once:
#   - shared ancestry with MiSTer-v5.15 AND with upstream's own MiSTer-v6.18, so GitHub
#     can compare and a PR is possible at all (across unrelated histories the compare
#     API 404s: "No common ancestor");
#   - a log with NO MiSTer commits of theirs in it — they are siblings, not ancestors —
#     so nothing lists a change that is absent from the tree. Parenting on the branch TIP
#     instead would list their commits whose changes this tree discards, and a reader
#     would see "xone: update driver" and conclude xone is present when it is a
#     Buildroot package now;
#   - a base commit whose diff against its parent is PURE upstream — 6.18.38 -> 6.18.50
#     stable, nothing else — because both trees are pristine tarballs. Parenting on
#     aba1ef4c1 instead would still work, but that diff would then be the whole
#     5.15.1 -> 6.18.50 delta and useless for review.
#
# Their branch is never touched: it becomes a sibling, exactly as MiSTer-v5.14 already
# is. What each of its commits became — carried, superseded upstream, or dropped — is
# recorded in MISTER-KERNEL-PATCH-RECON.md, which cites the superseding vanilla commit.
# No git command can answer that: across this much context drift `git patch-id` matches
# nothing, so "is this commit in 6.18?" is semantic, not mechanical.
#
# Without --parent-repo the base commit is a root commit and the branch is an orphan —
# fine for a standalone tree, but it cannot be PR'd anywhere.
#
# This script NEVER touches a fork or a remote. To publish, fetch the orphan branch
# into a fork and push from there (see EXPORT.md, which spells out the two commands).
#
# DETERMINISM
# -----------
# Reproducibility comes from two choices:
#   - `git am --committer-date-is-author-date`, so committer dates come from the
#     patches rather than from the clock;
#   - the base commit's date is the extracted Makefile's mtime. kernel.org tarballs are
#     produced with `git archive`, so every file carries the tag's commit time — stable
#     across machines and meaningful, unlike download time. Override with
#     SOURCE_DATE_EPOCH.
#
# Usage: scripts/export-kernel-tree.sh --output DIR [--parent-repo R --parent C]
#                                      [--onto COMMIT] [--fork-sync SHA] [--tarball FILE]
#                                      [--upstream-patches DIR] [--no-upstream-patches]
#
#   --output DIR      where to build the tree (must not already exist)
#   --parent-repo R   clone R and work inside it, rather than starting a fresh root
#   --parent C        spine commit to extend; a base commit is created on top of it
#                     from the pinned tarball (requires --parent-repo). Use the NEWEST
#                     pristine tarball commit on the spine -- for 6.18 that is
#                     d9ac12a691ead295c8bc6438754767b94c0f26a2 ("v6.18.38"), which
#                     already has upstream's own MiSTer-v6.18 hanging off it; parenting
#                     there is what makes the base commit's diff pure stable 6.18.38 ->
#                     the pinned version.
#   --onto COMMIT     replay onto COMMIT, which must ALREADY BE the pinned kernel
#                     version -- no base commit is created and the tarball is not
#                     used for the kernel. Use when upstream has published its own
#                     vanilla base to PR against; the result fast-forwards onto it.
#                     Mutually exclusive with --parent (requires --parent-repo).
#   --fork-sync SHA   fork commit this export was reconciled against; recorded in
#                     EXPORT.md as the backport-queue starting point
#   --tarball FILE    use this tarball instead of the dl/ cache or a download
#   --upstream-patches DIR
#                     the upstream-only series to replay after the carried one, instead
#                     of the derived default "<BR2_LINUX_KERNEL_PATCH>-upstream". These
#                     patches are NOT in the shipped image (see TWO SERIES above). An
#                     explicitly named directory must exist and be non-empty; the DERIVED
#                     one may be absent or empty, which simply means there are none.
#   --no-upstream-patches
#                     skip the upstream-only series entirely. The result is exactly the
#                     kernel the image ships — useful for diffing this tree against a
#                     Buildroot build, where the extra patches are the only expected
#                     difference and so make the comparison useless. Not what you want
#                     for a tree you intend to publish. Mutually exclusive with
#                     --upstream-patches.
#
# Exit: 0 = tree built and verified; non-zero = anything failed (fails closed).

set -o errexit
set -o nounset
set -o pipefail

# Assigned then marked readonly separately: `readonly X="$(cmd)"` masks cmd's exit status
# (shellcheck SC2155), and the rest of scripts/ avoids that pattern.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly HASH_FILE="$REPO_ROOT/board/mister/de10nano/patches/linux/linux.hash"

# WHICH FRAGMENTS THIS SCRIPT READS -- and why it is a STACK, not one file
# -----------------------------------------------------------------------
# This used to be `DEFCONFIG=configs/fragments/de10nano.fragment`, a single file, and
# that was correct only for as long as one file held every symbol. The 2026-09 fragment
# split ended that: configs/fragments/stacks.mk now composes the de10nano image from
# `common de10nano image-common de10nano-image`, and the kernel-module package selections
# (BR2_PACKAGE_XONE, BR2_PACKAGE_RTL8852CU_MORROWNR) moved into de10nano-image.fragment
# while the kernel pin stayed in de10nano.fragment.
#
# Reading one file after that split is not a partial answer, it is a WRONG one, and it
# fails in the worst possible direction: section 6b greps for BR2_PACKAGE_*=y, would have
# found NONE of them in de10nano.fragment, and its "detected zero kernel-module packages"
# guard would have aborted every export -- or, had that guard not existed, silently
# shipped a tree with no Xbox controller and no WiFi. So the fragment list comes from
# stacks.mk, which docs/buildroot-config.md §1 names as the single source of truth for
# what a configuration is made of, parsed through the same helper the other checks use.
# A future fragment move then needs no edit here.
#
# DE10NANO (the IMAGE stack), not DE10NANO_KERNEL: the exported tree is the kernel the
# MiSTer image ships, and the kernel-only stack deliberately selects no packages at all
# (stacks.mk: `image-common` is in every image stack and no kernel-only one), so reading
# it would reintroduce exactly the zero-drivers bug from the other direction.


# Committer identity for the generated commits. Patch AUTHORS are preserved by `git am`;
# this only says who mechanically produced the tree, and it must be explicit so the
# script works on a runner with no git config.
readonly EXPORT_NAME="${EXPORT_COMMITTER_NAME:-MiSTer Buildroot export}"
readonly EXPORT_EMAIL="${EXPORT_COMMITTER_EMAIL:-export@mister-devel.invalid}"

die() { printf 'export-kernel-tree: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s\n' "$*"; }

# Resolved AFTER die(), which it uses. STACK_FILES is the merge-ordered list of fragment
# files that make up the exported board's configuration; every read of a pinned value
# below goes through all of them, last definition winning, exactly as kconfig would.
STACK_FILES=("$REPO_ROOT/configs/mister_de10nano_defconfig")
readonly STACK_FILES
[ -f "${STACK_FILES[0]}" ] || die "no ${STACK_FILES[0]} -- the DE10 defconfig is the single source of the kernel pin (ADR 0030)"
unset _frag

# Only set when we download rather than use the dl/ cache. Cleaned on exit: it holds a
# ~150MB kernel tarball, so leaking it on every run is not a rounding error. --output is
# deliberately NOT touched here -- it is the deliverable, and it must survive a failure
# for the failure to be diagnosable.
#
# cleanup() uses `if` rather than `[[ ... ]] && rm`: as an EXIT trap, the function's own
# return status becomes the script's exit status, and a bare `[[ -n $download_dir ]]`
# returns 1 whenever nothing was downloaded -- making every successful cache-hit run exit
# 1 despite printing PASS.
# scratch_dir holds `git mailinfo` output while we read the upstream-only patches'
# Subject: lines; it is tiny but there is no reason to leak one per run.
download_dir=''
scratch_dir=''
cleanup() {
	if [[ -n $download_dir ]]; then
		rm -rf "$download_dir"
	fi
	if [[ -n $scratch_dir ]]; then
		rm -rf "$scratch_dir"
	fi
}
trap cleanup EXIT

output=''
fork_sync=''
tarball_override=''
parent_repo=''
parent=''
onto=''
upstream_patch_dir=''
skip_upstream=false

# Filled in from the parent commit itself when --parent is used (section 3); EXPORT.md's
# spine section is generated from them rather than naming a spine point that upstream has
# since moved past.
parent_short=''
parent_subject=''

while (($#)); do
	case "$1" in
	--output) output="${2:-}"; shift 2 ;;
	--parent-repo) parent_repo="${2:-}"; shift 2 ;;
	--parent) parent="${2:-}"; shift 2 ;;
	--onto) onto="${2:-}"; shift 2 ;;
	--fork-sync) fork_sync="${2:-}"; shift 2 ;;
	--tarball) tarball_override="${2:-}"; shift 2 ;;
	--upstream-patches) upstream_patch_dir="${2:-}"; shift 2 ;;
	--no-upstream-patches) skip_upstream=true; shift ;;
	# `q` on the closing line, not a bare range. A sed range RE-ARMS after it closes, and
	# this file contains a SECOND "# Usage:" -- the one in the build-mister-modules.sh
	# heredoc emitted in section 6c. Without the quit, the range reopened there, found no
	# second "# Exit:", and ran to end of file: --help printed ~300 lines of this script's
	# own source after the banner. Quitting at the first "# Exit:" prints the banner and
	# only the banner, regardless of what later sections contain.
	-h | --help)
		sed -n '/^# Usage:/,/^# Exit:/{p;/^# Exit:/q;}' "${BASH_SOURCE[0]}" |
			sed 's/^# \?//'
		exit 0
		;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

[[ -n $output ]] || die 'missing --output DIR (try --help)'
[[ ! -e $output ]] || die "--output already exists: $output"

# A parent is meaningless without the repo it lives in, and cloning a repo without saying
# where to hang the branch would silently fall back to an orphan.
[[ -n $parent_repo && -z $parent && -z $onto ]] && die '--parent-repo requires --parent or --onto'
[[ -n $parent && -z $parent_repo ]] && die '--parent requires --parent-repo'
[[ -n $onto && -z $parent_repo ]] && die '--onto requires --parent-repo'
[[ -n $parent && -n $onto ]] && die '--parent and --onto are mutually exclusive:
--parent extends a spine and CREATES a base commit from the tarball; --onto replays onto
a base that already exists. Pick one.'

# Naming a directory and then asking for it to be skipped is not a resolvable intent, and
# guessing either way would silently produce a tree the caller did not ask for -- one of
# which (the skipped one) is missing upstream's boot path.
[[ -n $upstream_patch_dir ]] && $skip_upstream &&
	die '--upstream-patches and --no-upstream-patches are mutually exclusive.'

# --- 1. Read the pinned inputs out of the config fragments -----------------------------
# The fragment stack is the single source of truth for what we build; nothing here is
# hardcoded, so a version bump is a one-line fragment edit and this script follows.

defconfig_value() {
	# Values look like: BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.38"
	#
	# Do NOT anchor on the closing quote. These fragments carry trailing comments on
	# some lines, and anchoring silently yields an empty value rather than failing --
	# which for an optional setting (a config fragment) would mean quietly dropping it.
	#
	# All stack files in MERGE ORDER, `tail -1` last: that is what kconfig does when a
	# later fragment redefines a symbol an earlier one set, so a value moved or overridden
	# across the 2026-09 split still resolves to the one the image is built with.
	sed -n "s/^$1=\"\([^\"]*\)\".*$/\1/p" "${STACK_FILES[@]}" | tail -1
}

# Buildroot spells the external tree's own path as a make variable inside the defconfig;
# resolve it the way Buildroot would.
resolve_br_path() {
	printf '%s' "${1//\$(BR2_EXTERNAL_MISTER_PATH)/$REPO_ROOT}"
}

version="$(defconfig_value BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE)"
[[ -n $version ]] ||
	die "BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE not set in the DE10 defconfig:
  ${STACK_FILES[*]}"

patch_dir="$(resolve_br_path "$(defconfig_value BR2_LINUX_KERNEL_PATCH)")"
config_file="$(resolve_br_path "$(defconfig_value BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE)")"
fragments="$(resolve_br_path "$(defconfig_value BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES)")"

[[ -d $patch_dir ]] || die "patch dir not found: $patch_dir"
[[ -f $config_file ]] || die "kernel config not found: $config_file"

# nullglob, or an empty patch dir yields an array holding the literal "*.patch" pattern
# -- length 1, so the guard below passes -- and `git am` then fails on a path that does
# not exist, blaming the patch rather than the empty directory.
shopt -s nullglob
series=("$patch_dir"/*.patch)
shopt -u nullglob
((${#series[@]})) || die "no patches in $patch_dir"

# --- 1b. The upstream-only series ------------------------------------------------------
# Patches this tree carries that the shipped image deliberately does not. See TWO SERIES
# at the top of this file for why that divergence exists and why it is not drift.
#
# The default path is DERIVED from the carried series rather than written out, for the
# same reason nothing else here is hardcoded: BR2_LINUX_KERNEL_PATCH is the one place
# that says where kernel patches live, and a second hardcoded copy of that path would go
# stale the first time the defconfig moved -- silently, by finding no directory and
# exporting a tree with upstream's boot mechanism quietly missing from it.

upstream_explicit=false
if [[ -n $upstream_patch_dir ]]; then
	upstream_explicit=true
	# Absolutize NOW, before anything globs it. The glob below runs in the invocation
	# cwd, but `git am` runs after the `cd "$output"` in section 4 -- so a RELATIVE
	# --upstream-patches yields relative paths that are unopenable by the time they are
	# applied, and git am's failure is reported as patch rot. That sends the operator off
	# to rebase a patch that was never broken. The carried series is immune only by
	# accident: it goes through resolve_br_path(), which substitutes an absolute
	# $REPO_ROOT. Left `-d`-guarded so a missing directory still hits the typo-vs-empty
	# die below rather than failing here with a worse message.
	if [[ -d $upstream_patch_dir ]]; then
		upstream_patch_dir="$(cd "$upstream_patch_dir" && pwd)" ||
			die "--upstream-patches: cannot resolve directory: $upstream_patch_dir"
	fi
else
	upstream_patch_dir="${patch_dir}-upstream"
fi

upstream_series=()
if $skip_upstream; then
	say 'Skipping the upstream-only series (--no-upstream-patches)'
	upstream_patch_dir=''
elif [[ -d $upstream_patch_dir ]]; then
	shopt -s nullglob
	upstream_series=("$upstream_patch_dir"/*.patch)
	shopt -u nullglob
elif $upstream_explicit; then
	# An explicitly named directory that is not there is a typo, not an empty series.
	# Treating it as empty would export a tree missing exactly the patches the caller
	# went out of their way to ask for, and report PASS.
	die "--upstream-patches: no such directory: $upstream_patch_dir"
fi

# Same rule for an explicitly named directory that exists but holds nothing: the caller
# asked for a series, so producing none is a failure. The DERIVED directory is different
# -- absent or empty there legitimately means "there are no upstream-only patches", which
# is the state this repo was in before the loop= patch existed.
$upstream_explicit && ((${#upstream_series[@]} == 0)) &&
	die "--upstream-patches: no *.patch files in $upstream_patch_dir"

# Read each upstream-only patch's Subject: and its reason for not being in the image, up
# front, BEFORE the tarball download and the whole series replay. A missing reason is a
# hard failure (see below), and discovering that after ten minutes of work would train
# people to skip the export rather than fix the patch.
#
# `git mailinfo` is used rather than a regex because it is the parser `git am` itself
# uses: it strips the "[PATCH 1/1] " prefix, unfolds continuation lines and decodes
# RFC2047-encoded headers, so the table below shows the same subject the commit will
# actually carry. scripts/lint-kernel-patches.sh checks the same thing in CI.
readonly NOT_IN_IMAGE_FILE='not-in-image'
upstream_subjects=()
upstream_reasons=()

if ((${#upstream_series[@]})); then
	scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/export-kernel-tree-meta.XXXXXX")" ||
		die 'could not create a temporary directory'

	for up_patch in "${upstream_series[@]}"; do
		up_name="$(basename "$up_patch")"

		up_info="$(git mailinfo "$scratch_dir/msg" "$scratch_dir/patch" <"$up_patch" 2>/dev/null)" ||
			die "git mailinfo could not parse $up_name. Run scripts/lint-kernel-patches.sh."

		# The exit status above is NOT the signal for a malformed identity, and relying on
		# it would leave the fast gate half-open. `git mailinfo` exits 0 while leaving
		# Author/Email EMPTY for a `From:` it cannot parse -- which is why
		# scripts/lint-kernel-patches.sh checks the fields rather than the status, and why
		# that script exists at all: this repo shipped exactly that defect once
		# (0013-hid-flydigi-vader.patch carried `From: Alexey Melnikov` with no <email>).
		#
		# `git am` hard-fails on it later with "fatal: empty ident name (for <>) not
		# allowed" -- but "later" here means after the tarball download, the hash verify,
		# the clone, the extract and a 31-patch replay, and the failure arrives wearing the
		# generic series-replay error instead of naming the file and the line. Checking all
		# three fields the same way the lint does keeps this gate honest: everything `git am`
		# needs from the headers is validated before any expensive work starts.
		#
		# DUPLICATED ON PURPOSE -- KEEP IN SYNC WITH scripts/lint-kernel-patches.sh
		# --------------------------------------------------------------------------
		# The non-empty Author/Email/Subject criteria below are the same three checks
		# lint-kernel-patches.sh makes (see the `problems+=(...)` block there). They are
		# duplicated rather than shared because the two scripts have no common library and
		# sourcing one from the other would couple a CI-only linter to the export's runtime.
		# That is a deliberate trade, not an oversight: the cost is that a change to the
		# criteria HERE must be mirrored THERE, or CI and the export start disagreeing about
		# what a valid patch header is -- and the failure mode is a green lint followed by a
		# failed export, which is the exact confusion this gate exists to prevent.
		# If a third caller ever needs these checks, factor all three into a shared helper
		# instead of adding another copy.
		up_subject="$(sed -n 's/^Subject: //p' <<<"$up_info")"
		up_author="$(sed -n 's/^Author: //p' <<<"$up_info")"
		up_email="$(sed -n 's/^Email: //p' <<<"$up_info")"

		[[ -n $up_subject ]] ||
			die "no Subject: in $up_name — it would appear as a blank row in EXPORT.md's
upstream-only table, and 'git am' would have no commit message to write."

		[[ -n $up_author && -n $up_email ]] ||
			die "unparseable From: in $up_name — 'git am' needs \`Name <email>\` to write a
commit and dies with \"fatal: empty ident name (for <>) not allowed\".
  got: $(grep -m1 '^From:' "$up_patch" || echo '(no From: line at all)')
Run scripts/lint-kernel-patches.sh, which checks both series the same way."

		# WHY A REASON IS MANDATORY
		# -------------------------
		# EXPORT.md tells upstream reviewers, in a table, which patches are in this tree
		# but not in the MiSTer image and why. A row with an empty reason is worse than
		# no table at all: it has the shape of a reviewed decision without being one, and
		# it is exactly the kind of claim that goes unchallenged for years. So the reason
		# is an input to the export, not prose someone remembers to add afterwards.
		#
		# Two places it can come from, in this order:
		#
		#   1. a `Not-in-image:` line in the patch's own commit message — preferred,
		#      because it travels with the patch through rebases and re-exports;
		#   2. a row in the series directory's `not-in-image` file, keyed by filename —
		#      for patches imported VERBATIM from the fork, where editing the commit
		#      message would mean rewriting someone else's commit text just to satisfy
		#      a tool of ours.
		#
		# Read from the mailinfo-split message body, not the raw file: grepping the raw
		# patch would also match a `Not-in-image:` string inside a diff hunk.
		up_reason="$(sed -n 's/^Not-in-image:[[:space:]]*//p' "$scratch_dir/msg" | head -1)"
		if [[ -z $up_reason && -f "$upstream_patch_dir/$NOT_IN_IMAGE_FILE" ]]; then
			# awk with an exact first-field match rather than sed: the key is a
			# filename full of '.' and '-', which sed would read as a regex, and a
			# near-miss would silently match the wrong row. Exact equality cannot.
			# It also skips '#' comment lines for free -- their first field is the
			# comment, which is never a patch filename.
			up_reason="$(awk -v key="$up_name" \
				'$1 == key { $1 = ""; sub(/^[[:space:]]+/, ""); print; exit }' \
				"$upstream_patch_dir/$NOT_IN_IMAGE_FILE")"
		fi
		[[ -n $up_reason ]] || die "no stated reason why $up_name is absent from the MiSTer image.

Every patch in $upstream_patch_dir is carried for the exported
tree ONLY, and EXPORT.md publishes a table naming each one and why the image does not
apply it. Refusing to emit that table with a blank row. Add either:

  * a line  'Not-in-image: <one-line reason>'  to the patch's commit message, or
  * a row   '$up_name  <one-line reason>'  to
    $upstream_patch_dir/$NOT_IN_IMAGE_FILE"

		upstream_subjects+=("$up_subject")
		upstream_reasons+=("$up_reason")
	done
fi

branch="MiSTer-v${version%.*}" # 6.18.38 -> MiSTer-v6.18, matching the fork's convention
tag="mister-${version}"

say "Exporting Linux $version + ${#series[@]} carried patches + ${#upstream_series[@]} upstream-only -> $output (branch $branch)"

# --- 2. Get the tarball, and verify it against the signed-manifest hash ----------------
# Fails closed: an unverified kernel tarball is the whole reason linux.hash exists.

tarball="$tarball_override"
if [[ -n $onto ]]; then
	# --onto: the base already exists upstream, so the kernel tarball is not needed and
	# no base commit is created. The safety property still has to hold, though -- replaying
	# a 6.18 series onto, say, a 5.15 base must not be attempted -- so the version is read
	# back out of the target commit's own Makefile below rather than trusted.
	say "Replaying onto existing base $onto (no base commit created)"
elif [[ -z $tarball ]]; then
	cached="$REPO_ROOT/dl/linux/linux-$version.tar.xz"
	if [[ -f $cached ]]; then
		tarball="$cached"
		say "Using cached tarball: $tarball"
	else
		# Explicit template, matching scripts/ci-tests.sh and scripts/check-linux-img.sh:
		# bare `mktemp -d` is a GNU extension and errors out on BSD/macOS mktemp, which
		# wants one. (`-t` is not the answer either -- GNU deprecates it and BSD reads
		# its argument as a prefix rather than a template.)
		download_dir="$(mktemp -d "${TMPDIR:-/tmp}/export-kernel-tree.XXXXXX")" ||
			die 'could not create a temporary download directory'
		tarball="$download_dir/linux-$version.tar.xz"
		url="https://cdn.kernel.org/pub/linux/kernel/v${version%%.*}.x/linux-$version.tar.xz"
		say "Downloading $url"
		curl --fail --location --silent --show-error --output "$tarball" "$url" ||
			die "download failed: $url"
	fi
fi

expected=''
if [[ -z $onto ]]; then
	[[ -f $tarball ]] || die "no such tarball: $tarball"

	expected="$(sed -n "s/^sha256[[:space:]]\+\([0-9a-f]\{64\}\)[[:space:]]\+linux-$version\.tar\.xz$/\1/p" "$HASH_FILE" | tail -1)"
	[[ -n $expected ]] || die "no sha256 for linux-$version.tar.xz in $HASH_FILE — bump the hash from kernel.org's signed manifest"

	actual="$(sha256sum "$tarball" | cut -d' ' -f1)"
	[[ $actual == "$expected" ]] || die "tarball hash mismatch for linux-$version.tar.xz
  expected $expected (from $HASH_FILE)
  actual   $actual"
	say "Tarball verified: sha256 $actual"
fi

# --- 3. Extract ------------------------------------------------------------------------

if [[ -n $onto ]]; then
	# Resolve the ref in the SOURCE repo and carry the SHA into the clone. Ref names are
	# ambiguous across a clone boundary and it is not a theoretical problem: `git clone`
	# copies the source's LOCAL branches to origin/*, so `--onto origin/MiSTer-v6.18`
	# resolves inside the clone to the source's own local MiSTer-v6.18 -- a different
	# commit from the origin/MiSTer-v6.18 the caller meant. That silently replayed a
	# series onto a tree that already had it applied, and the version check could not
	# catch it because both trees were the same Linux version.
	onto="$(git -C "$parent_repo" rev-parse --verify --quiet "$onto^{commit}")" ||
		die "--onto is not a commit in $parent_repo"
	say "Resolved --onto to $onto in $parent_repo"

	say "Cloning $parent_repo"
	git clone --quiet --no-checkout "$parent_repo" "$output" || die "clone failed: $parent_repo"
	git -C "$output" rev-parse --verify --quiet "$onto^{commit}" >/dev/null ||
		die "$onto is not reachable in the clone of $parent_repo"
	git -C "$output" checkout --quiet --detach "$onto"

	# The base is someone else's, so verify it is the version we are about to patch
	# rather than assuming. Read it from the target's own Makefile: replaying a 6.18
	# series onto a 5.15 base would otherwise fail deep in `git am` with conflicts that
	# look like bad patches instead of a bad base.
	onto_version="$(sed -nE 's/^VERSION = //p;s/^PATCHLEVEL = /./p;s/^SUBLEVEL = /./p' \
		"$output/Makefile" | head -3 | tr -d '\n')"
	[[ $onto_version == "$version" ]] || die "--onto $onto is Linux $onto_version, but this
repo pins $version (BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE). Refusing to replay a $version
patch series onto a $onto_version base."
	say "Base verified: $onto is Linux $onto_version"
elif [[ -n $parent_repo ]]; then
	say "Cloning $parent_repo to extend its spine at $parent"
	git clone --quiet --no-checkout "$parent_repo" "$output" || die "clone failed: $parent_repo"
	git -C "$output" rev-parse --verify --quiet "$parent^{commit}" >/dev/null ||
		die "--parent $parent is not a commit in $parent_repo"

	# Identify the spine point for EXPORT.md, from the commit itself rather than from a
	# hardcoded name. The newest spine point moves with upstream -- it was aba1ef4c1
	# "v5.15.1", it is d9ac12a69 "v6.18.38" now -- and a document that names the wrong
	# one sends a reviewer to compute the wrong diff. Short SHA is asked for at 9 digits
	# to match the width the rest of this repo's prose uses for this fork.
	parent_short="$(git -C "$output" rev-parse --short=9 "$parent^{commit}")"
	parent_subject="$(git -C "$output" log --format=%s -1 "$parent^{commit}")"

	# Detach at the spine point, then replace the worktree wholesale with the new
	# tarball. `git add --all` stages the deletions and the additions together, so the
	# resulting commit's tree is the pristine tarball and its parent is the spine.
	git -C "$output" checkout --quiet --detach "$parent"
	find "$output" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
else
	mkdir -p "$output"
fi

if [[ -z $onto ]]; then
	say "Extracting"
	tar -xf "$tarball" -C "$output" --strip-components=1
fi

# kernel.org tarballs come from `git archive`, so every file's mtime is the tag's commit
# time. That makes this stable across machines, unlike the download time.
if [[ -n ${SOURCE_DATE_EPOCH:-} ]]; then
	base_epoch="$SOURCE_DATE_EPOCH"
elif [[ -n $onto ]]; then
	# No tarball here, so take the base's own commit date. Still deterministic: it is a
	# property of the commit we were pointed at, not of when this script ran.
	base_epoch="$(git -C "$output" log --format='%ct' -1 "$onto")"
else
	base_epoch="$(stat -c %Y "$output/Makefile")"
fi
base_date="$(date -u -d "@$base_epoch" '+%Y-%m-%dT%H:%M:%S+00:00')"

# --- 4. Base commit: pristine upstream, on its own ---------------------------------------
# Kept as its own commit so `git diff <base> HEAD` is exactly the MiSTer delta and
# nothing else — the review question worth answering.

cd "$output"
[[ -n $parent_repo ]] || git init --quiet --initial-branch="$branch"
git config user.name "$EXPORT_NAME"
git config user.email "$EXPORT_EMAIL"
git config commit.gpgsign false

if [[ -n $onto ]]; then
	# The base commit is upstream's; ours would be a duplicate. Branch and go straight to
	# the series, so the result fast-forwards onto their branch and the PR is exactly our
	# delta -- nothing of theirs restated.
	base_commit="$(git rev-parse HEAD)"
	# -B, not -b. `git clone` copies the source repo's LOCAL branches, so as soon as the
	# parent repo has its own MiSTer-v6.18 checked out -- which it does the moment anyone
	# fetches a previous export back into it -- `-b` dies with "a branch named
	# 'MiSTer-v6.18' already exists" after the clone and the base verification have already
	# succeeded. That made the export's success depend on the parent repo's branch state
	# rather than on its commits, so it passed the first time and failed forever after.
	# Overwriting is right here and not destructive: $output is a throwaway clone this
	# script just created, the ref being replaced is a COPY of the parent's, and the real
	# publish step is an explicit fetch out of this directory (see EXPORT.md).
	git checkout --quiet -B "$branch"
else

# Subject is bare "v6.18.38" to match the spine's existing convention (v5.13.12, v5.14,
# v5.14.5, v5.15.1) — the branch should read as the next entry, not a foreign import.
#
# --force is load-bearing, not defensive. The kernel ships .gitignore files that match
# paths it also tracks, so a plain `git add` after a tarball extract silently drops
# them. That is not hypothetical: it is exactly why this repo's own v5.15.1 base is NOT
# byte-identical to kernel.org's v5.15.1 — 11 files (Documentation/.yamllint,
# fs/*/.kunitconfig, selftests/bpf/test_progs.c, selftests/arm64/tags/* to the `tags`
# ctags pattern, ...) are simply absent from it. Without --force we would reproduce that
# bug here and lose Documentation/.renames.txt from 6.18.38.
git add --all --force
GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
	git commit --quiet --file=- <<EOF
v$version

Pristine upstream kernel $version, unpacked from linux-$version.tar.xz as
published on kernel.org.

  sha256 $expected

Verified against the pinned hash in Buildroot_MiSTer, itself transcribed from
kernel.org's PGP-signed release manifest.

No MiSTer change is present in this commit -- it is upstream and nothing else,
exactly like the v5.13.12/v5.14/v5.14.5/v5.15.1 commits it follows. Every MiSTer
delta is a separate commit on top, so a diff from this commit to the tip of
$branch is precisely the MiSTer patch series.
$(if [[ -n $parent_repo ]]; then printf '%s\n' "
Because this commit's parent is a pristine tarball commit too, the diff against
that parent is the pure upstream delta, with no MiSTer code on either side."; fi)
Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer. Do not edit this
tree directly; see EXPORT.md.
EOF
base_commit="$(git rev-parse HEAD)"
# -B for the same reason as the --onto path above: the clone carries a copy of the parent
# repo's local branches, so -b fails once the parent has a branch of this name.
[[ -n $parent_repo ]] && git checkout --quiet -B "$branch"
fi

# --- 5. Replay the carried series -------------------------------------------------------
# --committer-date-is-author-date keeps this reproducible: dates come from the patches,
# not the clock, so an unchanged series regenerates to identical SHAs.
#
# Author identity comes from each patch's own From:, which scripts/lint-kernel-patches.sh
# guarantees is parseable — `git am` hard-fails the whole series on a malformed one.

say "Replaying ${#series[@]} patches with git am"
if ! git am --committer-date-is-author-date "${series[@]}" >/dev/null 2>&1; then
	git am --abort 2>/dev/null || true
	die "git am failed. Run scripts/lint-kernel-patches.sh first — a malformed From:
line fails the whole series. If the headers are fine, a patch does not apply to
$version and the series needs rebasing onto it."
fi

applied="$(git rev-list --count "$base_commit"..HEAD)"
((applied == ${#series[@]})) ||
	die "expected ${#series[@]} commits, got $applied"
say "Applied $applied/${#series[@]} carried patches cleanly"

# --- 5b. Replay the upstream-only series ------------------------------------------------
# AFTER the carried series and BEFORE the defconfig commit, deliberately. That ordering is
# what makes the tree's history readable as two contiguous blocks: everything from the
# base up to carried_tip is exactly the kernel the image ships, and the block after it is
# exactly what this tree adds for upstream. EXPORT.md publishes both as `git diff` ranges
# computed from that layout, so reordering these steps silently changes what those
# one-liners mean.
#
# Same --committer-date-is-author-date as above: dates come from the patches, not the
# clock, so an unchanged series regenerates to identical SHAs.

carried_tip="$(git rev-parse HEAD)"
upstream_applied=0

if ((${#upstream_series[@]})); then
	say "Replaying ${#upstream_series[@]} upstream-only patches with git am"
	if ! git am --committer-date-is-author-date "${upstream_series[@]}" >/dev/null 2>&1; then
		git am --abort 2>/dev/null || true
		die "git am failed on the upstream-only series in $upstream_patch_dir.

These patches are never applied by Buildroot, so unlike the carried series NOTHING ELSE
in this repo exercises them -- an image build stays green while they rot against a new
kernel. Run scripts/lint-kernel-patches.sh for a malformed From:; otherwise a patch no
longer applies to $version and needs rebasing onto it."
	fi

	upstream_applied="$(git rev-list --count "$carried_tip"..HEAD)"
	((upstream_applied == ${#upstream_series[@]})) ||
		die "expected ${#upstream_series[@]} upstream-only commits, got $upstream_applied"
	say "Applied $upstream_applied/${#upstream_series[@]} upstream-only patches cleanly"
fi

# --- 6. In-tree defconfig, so the tree is usable without Buildroot ------------------------
# This is the step that makes the export worth shipping: `git clone && make` works, which
# is what a materialized tree is FOR and what `make linux` inside Buildroot cannot give.
#
# Buildroot consumes BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE by copying it to .config and
# running olddefconfig; `make MiSTer_defconfig` fills in defaults the same way, so the
# minimized file works unchanged as a defconfig.

say "Generating arch/arm/configs/MiSTer_defconfig"
if [[ -n $fragments ]]; then
	# Merge with the kernel's OWN merge_config.sh rather than reimplementing Buildroot's
	# merge. -m merges without invoking a compiler; -r keeps later fragments winning.
	read -r -a frag_list <<<"$fragments"
	KCONFIG_CONFIG=arch/arm/configs/MiSTer_defconfig \
		./scripts/kconfig/merge_config.sh -m -r -O arch/arm/configs \
		"$config_file" "${frag_list[@]}" >/dev/null 2>&1 ||
		die 'merge_config.sh failed merging the config fragments'
	mv arch/arm/configs/.config arch/arm/configs/MiSTer_defconfig 2>/dev/null || true
	config_note="merged from $(basename "$config_file") + $(printf '%s ' "${frag_list[@]##*/}")"
else
	cp "$config_file" arch/arm/configs/MiSTer_defconfig
	config_note="copied verbatim from $(basename "$config_file")"
fi

git add arch/arm/configs/MiSTer_defconfig
GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
	git commit --quiet --file=- <<EOF
ARM: configs: add MiSTer_defconfig

The kernel configuration this board ships, in the kernel's own minimized
defconfig form, so the tree builds standalone without Buildroot:

    make ARCH=arm MiSTer_defconfig
    make ARCH=arm zImage

$config_note, which is the exact configuration Buildroot builds
(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE) — the image and this tree cannot drift.

This is deliberately the minimized form rather than a full expanded .config: an
expanded one bakes in the generating toolchain (CONFIG_CC_VERSION_TEXT) and
every default, which pins a config to one machine and buries the ~500 lines that
are actually a decision under ~4000 that are not.

Linux-Kernel_MiSTer ships the OTHER form -- its arch/arm/configs/MiSTer_defconfig
is a full resolved .config, header and all ("Automatically generated file; DO
NOT EDIT", CONFIG_CC_VERSION_TEXT naming that maintainer's
arm-none-linux-gnueabihf-gcc 10.2.1). The two forms are not a disagreement about
the configuration:

    make ARCH=arm MiSTer_defconfig

resolves this minimized file to the SAME .config his full form already spells
out, for his toolchain -- that is what a defconfig IS, and it is why kconfig
ships savedefconfig. The only lines that can differ are the ones kconfig
derives from the compiler in front of it (CONFIG_CC_VERSION_TEXT,
CONFIG_GCC_VERSION, CONFIG_AS_VERSION, CONFIG_LD_VERSION, the CONFIG_CC_HAS_*
and CONFIG_TOOLS_SUPPORT_* probes), which is precisely the machine-pinning this
form leaves out.

If you want his form in this tree, generate it -- do not hand-edit it:

    make ARCH=arm MiSTer_defconfig && cp .config arch/arm/configs/MiSTer_defconfig

Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer.
EOF

# --- 6a. The DTB build-name alias upstream's Makefile expects ------------------------------
# GENERATED HERE, NEVER APPLIED BY BUILDROOT -- same class as the defconfig commit above.
#
# WHY THIS EXISTS
# ---------------
# Linux-Kernel_MiSTer carries its OWN board DTS as
# arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts -- note the underscore
# between "de10" and "nano" -- and lists socfpga_cyclone5_de10_nano.dtb in that
# directory's Makefile (verified on its MiSTer-v6.18 branch at c129b0fac, which lists BOTH
# names -- mainline's socfpga_cyclone5_de10nano.dtb and its own
# socfpga_cyclone5_de10_nano.dtb). That filename is upstream's build interface: the
# maintainer builds the shipped DTB with
#
#     make ... intel/socfpga/socfpga_cyclone5_de10_nano.dtb
#
# and the DTB in the stock release is that file's output.
#
# We do not carry a second DTS. Our 0004 patch instead patches VANILLA's
# socfpga_cyclone5_de10nano.dts (no underscore, added upstream in 144616a80889, v6.14),
# which did not exist when the 5.15 branch was written -- that is the better shape,
# because it keeps our delta a reviewable diff against a mainline file instead of a
# 700-line vendor copy. The cost is exactly one thing: `make
# intel/socfpga/socfpga_cyclone5_de10_nano.dtb` fails in our tree with "No rule to make
# target", so the maintainer's own build command does not work on the tree we hand him.
#
# That is a one-line problem, so it gets a one-line fix rather than a policy argument: a
# DTS whose entire body is `#include` of the patched vanilla file, under the name his
# Makefile expects, plus the matching dtb- entry. Both names then build, byte-identical
# output, and nothing in the shipped image changes -- Buildroot never sees this commit,
# and BR2_LINUX_KERNEL_INTREE_DTS_NAME still names the vanilla file.
#
# scripts/check-export-tree.sh builds BOTH .dtb targets and fails if their bytes differ,
# so the alias cannot silently drift into a second board description.

say 'Adding the socfpga_cyclone5_de10_nano.dtb build-name alias'
readonly ALIAS_DTS='arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts'
readonly VANILLA_DTS='arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts'
readonly SOCFPGA_DTS_MAKEFILE='arch/arm/boot/dts/intel/socfpga/Makefile'

# Fail closed rather than emit an alias to a file that is not there. If 0004 ever moves
# to a differently-named DTS, this commit would otherwise produce a tree in which the
# maintainer's build command fails at the #include instead of at the missing target --
# a strictly worse error, arriving later.
[[ -f $VANILLA_DTS ]] ||
	die "$VANILLA_DTS is not in the tree, so the
$(basename "$ALIAS_DTS") build-name alias would #include a file that does not exist.
Has the carried DTS patch (0004) changed which file it patches?"
[[ ! -e $ALIAS_DTS ]] ||
	die "$ALIAS_DTS already exists in the tree.
The carried series now provides it, so this generated alias would overwrite someone
else's file. Remove this section instead of shadowing it."
grep -q "$(basename "$VANILLA_DTS" .dts)\.dtb" "$SOCFPGA_DTS_MAKEFILE" ||
	die "no $(basename "$VANILLA_DTS" .dts).dtb line in $SOCFPGA_DTS_MAKEFILE --
cannot place the alias next to it. Upstream restructured this Makefile; update this
section rather than appending the entry somewhere arbitrary."

cat >"$ALIAS_DTS" <<ALIASEOF
// SPDX-License-Identifier: GPL-2.0+
/*
 * socfpga_cyclone5_de10_nano.dts -- build-name alias.
 *
 * Linux-Kernel_MiSTer keeps the MiSTer DE10-Nano board description in a file
 * of THIS name (with the underscore) and builds the shipped DTB as
 * socfpga_cyclone5_de10_nano.dtb. This tree instead patches mainline's
 * socfpga_cyclone5_de10nano.dts (no underscore) -- same board, reviewable as a
 * diff against upstream -- so this file exists purely so that the historical
 * .dtb filename still builds, and builds the same bytes.
 *
 * There is no board content here and none may be added: put it in
 * socfpga_cyclone5_de10nano.dts, which is what the MiSTer image actually ships.
 *
 * Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer.
 */
#include "$(basename "$VANILLA_DTS")"
ALIASEOF

# Insert the dtb- entry immediately after the vanilla one rather than appending. This is
# ONE backslash-continued `dtb-$(CONFIG_ARCH_INTEL_SOCFPGA) +=` assignment, so a line
# appended after the last entry lands after the line that has NO trailing backslash and
# is silently not part of the list at all -- the file still parses, the target still does
# not exist, and the only symptom is the failure this whole section exists to remove.
# Duplicating the vanilla line and renaming the copy also preserves the leading tab and
# the trailing " \" exactly, which is why the substitution is done on a copy of $0
# rather than by printing a hand-built line.
#
# The `/\\$/` guard is the other half of that: it refuses to duplicate an entry that is
# the LAST in the list, because the copy would then be the orphaned line described above.
# awk rather than `sed -i`: -i needs an argument on BSD sed and this script runs on both.
awk -v vanilla="$(basename "$VANILLA_DTS" .dts).dtb" \
	-v alias="$(basename "$ALIAS_DTS" .dts).dtb" '
	{ print }
	!done && $1 == vanilla && /\\$/ {
		line = $0
		sub(vanilla, alias, line)
		print line
		done = 1
	}
	END { if (!done) exit 1 }
' "$SOCFPGA_DTS_MAKEFILE" >"$SOCFPGA_DTS_MAKEFILE.new" ||
	die "could not place $(basename "$ALIAS_DTS" .dts).dtb next to
$(basename "$VANILLA_DTS" .dts).dtb in $SOCFPGA_DTS_MAKEFILE: no continued dtb- line
carries it. Upstream restructured this Makefile -- update this section."
mv "$SOCFPGA_DTS_MAKEFILE.new" "$SOCFPGA_DTS_MAKEFILE"

grep -q "$(basename "$ALIAS_DTS" .dts)\.dtb" "$SOCFPGA_DTS_MAKEFILE" ||
	die "failed to add $(basename "$ALIAS_DTS" .dts).dtb to $SOCFPGA_DTS_MAKEFILE"

git add --force "$ALIAS_DTS" "$SOCFPGA_DTS_MAKEFILE"
GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
	git commit --quiet --file=- <<EOF
ARM: dts: socfpga: add socfpga_cyclone5_de10_nano.dts build-name alias

Linux-Kernel_MiSTer carries its own board DTS as socfpga_cyclone5_de10_nano.dts
(with the underscore) and builds the shipped device tree as
socfpga_cyclone5_de10_nano.dtb:

    make ARCH=arm CROSS_COMPILE=... intel/socfpga/socfpga_cyclone5_de10_nano.dtb

This tree does not carry a second board DTS. It patches mainline's
socfpga_cyclone5_de10nano.dts (no underscore, 144616a80889, v6.14) instead, so
the MiSTer delta stays a reviewable diff against an upstream file rather than a
vendor copy. Without this commit the build command above fails with "No rule to
make target" on a tree that is otherwise complete.

So: a one-line DTS that #includes the patched file, under the name the old
Makefile entry expects, and the matching dtb-\$(CONFIG_ARCH_INTEL_SOCFPGA)
entry next to the existing one. Both .dtb names now build and their output is
byte-identical -- scripts/check-export-tree.sh builds both and compares them, so
this cannot drift into a second, diverging board description.

Not applied to the MiSTer image: Buildroot builds the vanilla name directly and
never reads this commit. Generated by scripts/export-kernel-tree.sh in
Buildroot_MiSTer.
EOF

# --- 6b. Vendor the out-of-tree kernel modules -------------------------------------------
# Without this the exported tree builds a kernel with no Xbox (xone) and no 11ac WiFi,
# while the 5.15 fork has both vendored in-tree — a silent feature regression for anyone
# who builds this tree expecting what MiSTer ships.
#
# WHY THE SOURCES ARE VENDORED BUT NOT WIRED INTO Kconfig
# -------------------------------------------------------
# The obvious thing is in-tree integration (Kconfig symbol + `obj-$(CONFIG_X) += dir/`),
# the way the fork does it. It is not safe for these packages, and the reason is in the
# Realtek Makefiles, above their own `ifneq ($(KERNELRELEASE),)` guard:
#
#     export TopDIR ?= $(shell pwd)
#     $(shell cp $(TopDIR)/autoconf_..._linux.h $(TopDIR)/include/autoconf.h)
#
# That is parse-time filesystem mutation keyed off `pwd`. In an in-tree build `pwd` is the
# KERNEL ROOT, not the module directory, so TopDIR points at the wrong tree and the
# driver's generated autoconf.h silently never appears -- `$(shell ...)` swallows the
# error. These 2594-line Makefiles are built on the assumption that they are never
# in-tree, across ~1900 files of driver. Wiring them in-tree would mean inventing hooks no
# upstream tests, then patching upstream Makefiles we would have to maintain forever.
#
# rtl8852cu-morrownr (the newer Realtek "phl" tree) reaches the same conclusion by a
# slightly different route, worth noting so nobody re-tests the old one and declares it
# fixed: it does still `export TopDIR ?= $(shell pwd)` (its Makefile:319) but its
# `$(shell cp ... autoconf.h)` is gated off by `CONFIG_AUTOCFG_CP = n` (:67, guard at
# :465), so THAT specific mutation is inactive. The pwd dependence is not -- `DRV_PATH ?=
# $(TopDIR)` (:323) is what `include $(wildcard $(DRV_PATH)/platform/*.mk)` resolves
# against, and in an in-tree build that misses platform/autodetect.mk entirely, taking
# -DCONFIG_IOCTL_CFG80211 and the rest of the flag set with it. Same verdict: out-of-tree
# only.
#
# So the sources go in at the paths the fork uses (the tree LOOKS like the fork's), and
# they are built through the exact out-of-tree invocation Buildroot already uses -- which
# is upstream's own supported path, and is proven daily by our own image builds. The
# recipe is read from each package's .mk rather than reinvented here, which is also what
# keeps a package bump cheap: change the pin in the .mk, re-run, done.
#
# xone is a partial exception -- 41 files, a clean Kbuild -- but its `obj-m :=` is declared
# UNCONDITIONALLY, never gated on CONFIG_XONE, so an in-tree Kconfig symbol for it would be
# decorative: present, and doing nothing. Two mechanisms in one tree is also harder to
# explain than one. It goes through the same path as the rest.

# Package -> in-tree path. The only hand-maintained mapping here, kept declarative on
# purpose. Every kernel-module package gets an entry, not just the currently-enabled ones,
# so flipping one on in the defconfig needs no edit here.
# The seven deselected Realtek fork rows this table used to carry (rtl8812au,
# rtl8814au-morrownr, rtl8821au-morrownr, rtl8821cu-morrownr, rtl88x2bu,
# rtl8188eu-aircrack-ng, rtl8188fu) went away with the packages on 2026-09-10.
# They were the "just-in-case" half of the note above; with the packages gone
# there is nothing for them to map. Every row below is now on the live path.
declare -A MODULE_PATH=(
	[xone]='drivers/hid/xone'
	# rtl8852cu-morrownr is a WiFi fork the image SHIPS (v10.2, ADR 0016 —
	# mainline rtw89 has no rtw8852cu.c). Naming rule: the fork suffix is a
	# Buildroot package-name concern, and the in-tree path uses the plain chip
	# name the 5.15 fork would have used.
	[rtl8852cu-morrownr]='drivers/net/wireless/realtek/rtl8852cu'
)

# Packages deliberately NOT exported, with the reason. This is a separate set
# from "has no MODULE_PATH" so that forgetting a mapping still fails closed --
# the die below only accepts silence for a package named HERE.
declare -A MODULE_EXPORT_SKIP=(
	# aic8800 is the one driver where the fork went FIRST. Sorgelig vendored
	# the same AICSemi SDK snapshot into MiSTer-v6.18 himself
	# (c129b0fac34ad5d613bbec3f59d6036775e41c83, "Add AIC8800 WiFi/BT
	# driver.", at drivers/net/wireless/aic8800), so exporting ours would
	# hand upstream a copy of something it already has, at the same path, and
	# collide there. The export exists to carry OUR delta; this is not one.
	#
	# It would also need machinery nothing else here has. Unlike every other
	# kernel-module package, this one's sources are not at the tarball root:
	# the tarball is radxa-pkg's whole 55 MiB multi-bus repository and the
	# module tree lives at src/USB/driver_fw/drivers/aic8800 (hence
	# AIC8800_MODULE_SUBDIRS). The `tar --strip-components=1` below would
	# vendor the PCIE and SDIO drivers and the Debian packaging along with it.
	# And the sources are only buildable AFTER upstream's own
	# debian/patches/series is applied -- see package/aic8800/aic8800.mk --
	# which the exporter has no notion of. If this ever does need exporting,
	# teach the loop MODULE_SUBDIRS and the patch series first; do not just
	# add a MODULE_PATH row.
	[aic8800]='stock vendors its own copy at the same path (MiSTer-v6.18 c129b0fac3)'
)

# A package is a kernel module iff its .mk evals Buildroot's kernel-module infra. Detected
# rather than listed, so a new one cannot be missed by forgetting to update a list here.
#
# The `=y` is NOT anchored to end-of-line: these fragments annotate most package lines
# with a trailing comment ("BR2_PACKAGE_RTL8812AU=y    # RTL8812AU 11ac -- ..."), and
# anchoring matched only the one line without one, silently vendoring xone alone and
# dropping all three WiFi drivers.
#
# Read over the WHOLE STACK, not one fragment. The package selections live in
# de10nano-image.fragment since the 2026-09 split while the kernel pin stayed in
# de10nano.fragment; reading only the latter finds zero packages (see the STACK_FILES
# note near the top).
#
# LAST DEFINITION WINS, the same rule defconfig_value() implements with `tail -1` and
# the same rule kconfig itself applies when a later fragment redefines a symbol an
# earlier one set. This used to be a bare `sed` for `=y` only, with a comment claiming
# "`# BR2_PACKAGE_X is not set` lines cannot match -- the pattern is anchored at column 1
# on the symbol -- so a disabled driver stays disabled." That had it exactly backwards:
# because the sed matched ONLY `=y`, a later fragment's not-set line was invisible, so a
# symbol set `=y` early and disabled later still read as enabled. The export would then
# vendor a driver the image does not ship, and emit a build-mister-modules.sh line for
# it -- silently, because check-export-tree.sh compares only the carried tip, which is
# before the vendoring commits.
#
# Nothing in the tree triggers it today (no kernel-module package carries a not-set line
# in any DE10 fragment), so this is a latent bug being closed rather than a live one
# being fixed. The awk tracks both forms in merge order and emits only symbols whose
# FINAL state is enabled.
mapfile -t enabled_kmods < <(
	awk '
		/^BR2_PACKAGE_[A-Z0-9_]+=y([ \t].*)?$/ {
			sym = $0; sub(/=y.*$/, "", sym)
			if (!(sym in seen)) { order[++n] = sym; seen[sym] = 1 }
			state[sym] = 1; next
		}
		/^#[ \t]*BR2_PACKAGE_[A-Z0-9_]+[ \t]+is not set/ {
			sym = $2
			if (!(sym in seen)) { order[++n] = sym; seen[sym] = 1 }
			state[sym] = 0; next
		}
		END { for (i = 1; i <= n; i++) if (state[order[i]]) print order[i] }
	' "${STACK_FILES[@]}" |
		while read -r sym; do
			dir="$(tr 'A-Z_' 'a-z-' <<<"${sym#BR2_PACKAGE_}")"
			mk="$REPO_ROOT/package/$dir/$dir.mk"
			[[ -f $mk ]] || continue
			# shellcheck disable=SC2016 # literal Makefile text being matched with
			# grep -F, not a shell expression -- must stay single-quoted.
			grep -qF '$(eval $(kernel-module))' "$mk" || continue
			printf '%s\n' "$dir"
		done
)

((${#enabled_kmods[@]})) || die "detected zero kernel-module packages in the
DE10 defconfig (configs/mister_de10nano_defconfig):
  ${STACK_FILES[*]}
That is almost certainly a parsing bug in this script rather than the truth — the image
ships xone and the Realtek WiFi drivers. Refusing to export a tree missing them.
If the defconfig moved, fix STACK_FILES in this script;
do NOT relax this check."

# Announce what will actually be vendored, not what was detected: the two differ
# whenever MODULE_EXPORT_SKIP names something (aic8800 does today). Saying
# "Vendoring 3" and then committing 2 is the same off-by-one the RESULT-line
# arithmetic below exists to avoid.
vendor_pkgs=()
skip_pkgs=()
for pkg in "${enabled_kmods[@]}"; do
	if [[ -n ${MODULE_EXPORT_SKIP[$pkg]:-} ]]; then
		skip_pkgs+=("$pkg")
	else
		vendor_pkgs+=("$pkg")
	fi
done
say "Vendoring ${#vendor_pkgs[@]} out-of-tree kernel modules: ${vendor_pkgs[*]-}"
# `if`, not `((…)) && say`: this script runs under `set -o errexit`, and while bash
# exempts the left-hand side of an && list from it, the idiom is a trap worth not
# spelling out here (an empty skip list is the normal case).
if ((${#skip_pkgs[@]})); then
	say "  not vendored (MODULE_EXPORT_SKIP): ${skip_pkgs[*]}"
fi
module_build_lines=()
module_doc_rows=()

for pkg in "${enabled_kmods[@]}"; do
	upper="$(tr 'a-z-' 'A-Z_' <<<"$pkg")"
	mk="$REPO_ROOT/package/$pkg/$pkg.mk"
	dest="${MODULE_PATH[$pkg]:-}"

	# Deliberate, named omission -- announced, never silent.
	if [[ -n ${MODULE_EXPORT_SKIP[$pkg]:-} ]]; then
		say "  skipping $pkg: ${MODULE_EXPORT_SKIP[$pkg]}"
		continue
	fi

	# Fail closed. Silently skipping an enabled driver is exactly the regression this
	# whole section exists to prevent.
	[[ -n $dest ]] || die "no in-tree path mapped for kernel-module package '$pkg'.
Add it to MODULE_PATH in $(basename "${BASH_SOURCE[0]}"), or -- if leaving it out is
deliberate -- to MODULE_EXPORT_SKIP with the reason. Refusing to export a tree that
silently omits a driver the image ships."

	pkg_version="$(sed -n "s/^${upper}_VERSION = //p" "$mk" | tail -1)"
	[[ -n $pkg_version ]] || die "no ${upper}_VERSION in $mk"
	pkg_opts="$(sed -n "s/^${upper}_MODULE_MAKE_OPTS = //p" "$mk" | tail -1)"

	# EXPORTED_LINUX_DIR. One option value has to be TRANSLATED rather than copied:
	# rtl8852cu-morrownr passes KSRC=$(LINUX_DIR) (its Makefile probes the kernel
	# version through KSRC and, left at platform/autodetect.mk's default of
	# /lib/modules/$(uname -r)/build, silently drops every ccflag -- see that .mk).
	# $(LINUX_DIR) is a Buildroot make variable. Emitted verbatim into
	# build-mister-modules.sh it would become bash COMMAND SUBSTITUTION of a command
	# named LINUX_DIR -- and, checked rather than assumed, `set -o errexit` does NOT
	# catch that. The emitted line is `build_module <dir> CONFIG_RTL8852CU=m
	# KSRC=$(LINUX_DIR)`: a simple command with arguments, not an assignment-only
	# command, and a failed command substitution inside an ARGUMENT word does not
	# become the enclosing command's exit status. Ran the exact shape under
	# `set -o errexit; set -o nounset; set -o pipefail` (the generated script's own
	# preamble): bash printed "LINUX_DIR: command not found" to stderr, build_module
	# still ran with KSRC= EMPTY, the next line executed, and the script exited 0.
	# So the silent empty-KSRC build -- every ccflag dropped, including
	# -I$(src)/include and -DCONFIG_RTL8852C -- is the DEFAULT outcome, not a
	# hypothetical one behind relaxed errexit. That makes this translation
	# load-bearing, not belt-and-braces. The exported tree's equivalent is its own
	# $KDIR, double-quoted in the replacement so a path with spaces survives; the `$`
	# is backslash-escaped below so THIS script does not expand it.
	pkg_opts="${pkg_opts//\$(LINUX_DIR)/\"\$KDIR\"}"

	# Fail closed on any OTHER $(...) make variable: an option added later that this
	# translation does not know about would be emitted verbatim and mis-execute the
	# same way. Better to stop the export than to ship a build script that does.
	# Written as `if`, not `[[ … ]] && die`, because a false test in an && list is a
	# non-zero status and `set -o errexit` (line 151) would abort the export on the
	# HAPPY path.
	# shellcheck disable=SC2016 # the single quotes are the POINT: this matches a
	# LITERAL "$(" substring in $pkg_opts. Expanding it here is exactly the bug
	# being detected. (CI runs `shellcheck -x` at default severity, which
	# includes info-level findings like SC2016 -- do not assume `-S warning`
	# locally is the same gate.)
	if [[ $pkg_opts == *'$('* ]]; then
		die "unhandled make variable in ${upper}_MODULE_MAKE_OPTS: $pkg_opts
build-mister-modules.sh is bash, not make, so \$(...) there is command substitution.
Add a translation next to the EXPORTED_LINUX_DIR note in $(basename "${BASH_SOURCE[0]}")."
	fi

	pkg_tar="$REPO_ROOT/dl/$pkg/$pkg-$pkg_version.tar.gz"
	[[ -f $pkg_tar ]] || die "missing source tarball: $pkg_tar
Populate Buildroot's download cache first:  make $pkg-source"

	# Same fail-closed rule as the kernel: the hash file is authority, no hash no export.
	pkg_expected="$(sed -n "s|^sha256[[:space:]]\+\([0-9a-f]\{64\}\)[[:space:]]\+$pkg-$pkg_version\.tar\.gz$|\1|p" \
		"$REPO_ROOT/package/$pkg/$pkg.hash" | tail -1)"
	[[ -n $pkg_expected ]] || die "no sha256 for $pkg-$pkg_version.tar.gz in package/$pkg/$pkg.hash"
	pkg_actual="$(sha256sum "$pkg_tar" | cut -d' ' -f1)"
	[[ $pkg_actual == "$pkg_expected" ]] ||
		die "hash mismatch for $pkg-$pkg_version.tar.gz
  expected $pkg_expected
  actual   $pkg_actual"

	mkdir -p "$dest"
	tar -xzf "$pkg_tar" -C "$dest" --strip-components=1

	# --force again: these trees ship their own .gitignore files (build artifacts,
	# *.mod.c, Module.symvers). Without it we would drop tracked sources that happen to
	# match, the same way the fork's own v5.15.1 base lost 11 files.
	git add --force "$dest"
	GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
		git commit --quiet --file=- <<EOF
$pkg: vendor $pkg_version at $dest

Out-of-tree kernel module the MiSTer image ships, vendored here so this tree
builds what MiSTer actually runs rather than a kernel silently missing it.

  upstream  $(sed -n "s/^${upper}_SITE = //p" "$mk" | tail -1)
  pin       $pkg_version
  sha256    $pkg_expected

Sources are verbatim upstream, at the path the 5.15 branch uses. They are NOT
wired into Kconfig -- build them with ./build-mister-modules.sh, which uses this
package's own supported out-of-tree recipe. See that script for why.

Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer; the pin lives in
package/$pkg/$pkg.mk there.
EOF

	module_build_lines+=("build_module $dest${pkg_opts:+ $pkg_opts}")
	module_doc_rows+=("| \`$dest\` | $pkg_version | ${pkg_opts:-—} |")
done

# --- 6c. The build script, emitted from the .mk recipes ------------------------------------

say 'Writing build-mister-modules.sh'
cat >build-mister-modules.sh <<'MODEOF'
#!/usr/bin/env bash
#
# build-mister-modules.sh — build the out-of-tree drivers this tree vendors.
#
# The kernel builds with:
#     make ARCH=arm MiSTer_defconfig
#     make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage
#
# These drivers do NOT build from that, by design. They are vendored at the paths the
# 5.15 branch uses, but they are not wired into Kconfig, because their own Makefiles do
# parse-time work keyed off `$(shell pwd)`:
#
#     export TopDIR ?= $(shell pwd)
#     $(shell cp $(TopDIR)/autoconf_..._linux.h $(TopDIR)/include/autoconf.h)
#
# In an in-tree build `pwd` is the kernel root rather than the module directory, so that
# copy silently lands in the wrong place and the driver's generated autoconf.h never
# appears. These Makefiles assume they are always built out-of-tree. So that is how this
# builds them — which is upstream's own supported path, not a workaround.
#
# Usage: ./build-mister-modules.sh [ARCH] [CROSS_COMPILE]
#   defaults: arm, arm-linux-gnueabihf-
#
# REQUIRES A FULLY BUILT KERNEL FIRST -- not just `modules_prepare`:
#
#     make ARCH=arm MiSTer_defconfig
#     make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION= zImage modules
#     ./build-mister-modules.sh
#
# PASS `LOCALVERSION=` TO THE KERNEL BUILD, exactly as above. Empty, but SET.
#
# This tree is a git repo whose HEAD sits dozens of commits past the v<ver> base commit, so
# scripts/setlocalversion correctly concludes the source is modified and appends a "+",
# giving `6.18.38+`. Buildroot builds the same source from a tarball with no git around
# it, so its identical-but-also-patched kernel reports plain `6.18.38`. The two disagree
# only because one build can see its own history and the other cannot.
#
# That single "+" lands in vermagic, and vermagic is what the kernel matches on when
# loading a module:
#
#     vermagic=6.18.38+ SMP mod_unload ARMv7 p2v8     <- built here, without LOCALVERSION=
#     vermagic=6.18.38  SMP mod_unload ARMv7 p2v8     <- Buildroot, and this tree WITH it
#
# Mismatch that and modprobe rejects every module ("version magic ... should be ..."),
# which reads like a broken driver and is not. Setting LOCALVERSION= (even to empty)
# makes setlocalversion skip the "+" entirely, so this tree's kernel and modules are
# interchangeable with the shipped image's.
#
# `modules_prepare` is NOT enough, and the way it fails is worth knowing because the
# error blames the driver rather than the real cause. An external module is linked
# against the kernel's symbol table in Module.symvers, and that file is produced by
# modpost during `make modules`, which in turn needs vmlinux from the `zImage` build.
# Without it every kernel symbol the driver uses reads as undefined:
#
#     ERROR: modpost: "skb_pull" [8812au.ko] undefined!
#
# Nothing is wrong with the driver there -- the kernel symbol table simply is not built
# yet. Hence the check below, which says so directly.

set -o errexit
set -o nounset
set -o pipefail

readonly KDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ARCH="${1:-arm}"
readonly CROSS_COMPILE="${2:-arm-linux-gnueabihf-}"

[[ -f $KDIR/.config ]] || {
	printf 'No .config — run `make ARCH=%s MiSTer_defconfig` first.\n' "$ARCH" >&2
	exit 1
}

[[ -f $KDIR/Module.symvers ]] || {
	cat >&2 <<EOF
No Module.symvers — the kernel is not built yet, so modpost has no symbol table and
every kernel symbol these drivers use would be reported as undefined.

Build the kernel first, then re-run this:

    make ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE zImage modules

(\`modules_prepare\` alone does NOT produce Module.symvers -- it needs vmlinux.)
EOF
	exit 1
}

build_module() {
	local dir="$1"; shift
	printf '\n=== %s\n' "$dir"
	# Exactly what Buildroot's kernel-module infra invokes, including each driver's own
	# CONFIG_ override where its Makefile gates obj- behind one.
	#
	# LOCALVERSION= (set, but empty) is load-bearing -- see the note at the top of this
	# script. It must match the kernel build's, or these modules get a vermagic the
	# kernel rejects.
	make -C "$KDIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" LOCALVERSION= \
		M="$dir" "$@" modules
}

MODEOF
printf '%s\n' "${module_build_lines[@]}" >>build-mister-modules.sh
cat >>build-mister-modules.sh <<'MODEOF'

printf '\nBuilt .ko files:\n'
find . -name '*.ko' -newer .config -printf '  %p\n' 2>/dev/null | sort
MODEOF
chmod +x build-mister-modules.sh

git add --force build-mister-modules.sh
GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
	git commit --quiet --file=- <<EOF
build-mister-modules.sh: build the vendored out-of-tree drivers

The vendored drivers are not wired into Kconfig, so \`make zImage\` does not build
them. This does, using each package's own supported out-of-tree recipe as taken
from its Buildroot .mk -- the same invocation that builds the shipped image, not
a reimplementation of it.

Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer.
EOF

# --- 7. Say plainly what this tree is ----------------------------------------------------

# COMMIT ARITHMETIC — the two `git diff` one-liners EXPORT.md prints
# -----------------------------------------------------------------
# Those one-liners are how an upstream reviewer sees the MiSTer delta, so being off by N
# is silent, embarrassing, and very easy: the number of commits between the base and the
# tag is not just the patch count. It is
#
#     carried patches + upstream-only patches + defconfig + the DTB build-name alias
#     + one per vendored driver + build-mister-modules.sh + EXPORT.md
#
# and three of those terms grow on their own -- a new kernel-module package changes it
# without anyone touching this section. So it is MEASURED, not derived from a formula
# that has to be kept in sync. (The previous hand-derived `$((applied + 1))` was already
# wrong before the upstream-only series existed: with 31 carried patches it named a
# mid-series commit rather than the base, because it counted neither the defconfig, the
# three driver commits, the build script, nor EXPORT.md itself. Section 6a's alias commit
# was added later still and needed no change here for exactly that reason.)
#
# WHERE A NEW GENERATED COMMIT MAY GO. base_offset is measured, so it absorbs anything.
# shipped_offset is base_offset MINUS the carried count, so it only stays correct while
# every generated commit sits AFTER the carried series -- which is why section 6a's alias
# lands after the defconfig commit and not, say, next to the DTS patch it aliases.
# Putting a generated commit before or inside either series silently redefines what both
# EXPORT.md one-liners mean; section 8's assertions are what would catch it.
#
# HEAD is currently the build-script commit; EXPORT.md's own commit is not made yet, and
# the tag will land on it. Hence the +1. Section 8 asserts both offsets resolve to the
# commits claimed here rather than trusting this arithmetic.
base_offset=$(( $(git rev-list --count "$base_commit"..HEAD) + 1 ))
# The last carried patch: base + carried series = exactly what Buildroot applies.
# Offsets count BACKWARDS from the tag, so a commit later in the series has a SMALLER
# offset; the upstream-only block therefore ends nearer the tag than the carried one.
shipped_offset=$((base_offset - applied))
upstream_tip_offset=$((shipped_offset - upstream_applied))

# The upstream-only table, generated from the files actually present. Never hardcoded:
# the whole point is that adding a patch to that directory updates this document, so it
# cannot describe a series that has moved on without it.
#
# EXPORT.md is read by upstream reviewers, so "1 patch(es)" is not good enough for the
# one sentence in it that people will quote.
up_patch_noun='patches'
up_commit_noun='commits'
if ((upstream_applied == 1)); then
	up_patch_noun='patch'
	up_commit_noun='commit'
fi

upstream_section=''
if ((upstream_applied)); then
	upstream_section="## This tree is NOT the kernel the MiSTer image ships

It is that kernel **plus exactly $upstream_applied $up_patch_noun**, listed here. Every one is
carried for *this* tree only: Buildroot's \`BR2_LINUX_KERNEL_PATCH\` points at
\`board/mister/de10nano/linux-patches/\` and never sees them, so they are in no MiSTer
image this repo builds. They are here because Linux-Kernel_MiSTer is upstream's kernel
for every MiSTer, not only ours, and it has to keep working for all of them.

| patch | not in the MiSTer image because |
|---|---|
"
	for i in "${!upstream_series[@]}"; do
		# Escape pipes: a Subject: containing one would otherwise split the row into
		# extra columns and silently mangle the table.
		upstream_section+="| ${upstream_subjects[$i]//|/\\|} | ${upstream_reasons[$i]//|/\\|} |
"
	done
	upstream_section+="
They are the last $upstream_applied $up_commit_noun of the patch series here, immediately after
the carried ones, so the split is visible in the log as well as in this table:

    git log --oneline $tag~$shipped_offset..$tag~$upstream_tip_offset

"
else
	upstream_section="## This tree is the kernel the MiSTer image ships

There are no upstream-only patches in this export, so the series here is exactly the
series Buildroot applies — patch for patch, in the same order. (This repo can carry
patches for the exported tree alone, in
\`board/mister/de10nano/linux-patches-upstream/\`; that directory is empty or absent, or
the export was run with \`--no-upstream-patches\`.)

"
fi

# The spine section, generated from the parent commit rather than written out. Upstream's
# newest pristine tarball commit MOVES -- it was aba1ef4c1 "v5.15.1" when this script was
# written and is d9ac12a69 "v6.18.38" now -- and the whole value of the section is that a
# reviewer can run the `git diff` in it and get the pure upstream delta. A hardcoded SHA
# there would be wrong the first time the spine grew, and wrong silently: the diff would
# still be large and plausible, just against the wrong base.
spine_section='## Where this branch hangs'
if [[ -n $parent_short ]]; then
	spine_section+="

Linux-Kernel_MiSTer's tarball commits form a spine, and each \`MiSTer-vX.Y\` branch hangs
off a spine point with its MiSTer series replayed on top. Every spine commit is a
pristine upstream tarball with no MiSTer code in it. This branch extends that spine the
same way, so it is the next entry rather than a foreign import:

    e12ed6c19 v5.13.12 -> 137491a75 v5.14 -> b6f2ca1c4 v5.14.5 -> aba1ef4c1 v5.15.1
                                                                       |
              +--------------------------------------------------------+
              |
              +-- [MiSTer commits] -> MiSTer-v5.15         (theirs, untouched)
              |
              +-- $parent_short $parent_subject   <- this branch's parent, a pristine tarball
                           |
                           +-- [their MiSTer commits]      (theirs, untouched)
                           |
                           +-- v$version -> [$applied carried + $upstream_applied upstream-only
                                              + generated] -> $branch

The branches already hanging off those spine points are **not modified and not
ancestors** — they are siblings. Nothing was lost.

Two consequences worth knowing:

- The base commit's parent, \`$parent_short\` (\`$parent_subject\`), is itself a pristine
  tarball commit, so \`git diff $parent_short $tag~$base_offset\` is a **pure upstream
  delta** — $parent_subject to $version, with no MiSTer code on either side. That is the
  diff to read when the question is \"what did the stable series change\", and it is only
  that clean because both ends are tarballs.
- No MiSTer commit of theirs appears in this branch's log, which is the point: this tree
  does not contain most of them, and a log listing changes that are absent from the
  tree would be worse than no log at all.
"
elif [[ -n $onto ]]; then
	spine_section+="

This export was made with \`--onto\`: the base is upstream's own pristine
$version commit, not one this export created, and the series here fast-forwards onto it.
So there is no new spine entry to draw — this branch simply continues theirs, and a PR
from it is exactly the MiSTer delta with nothing of theirs restated.
"
else
	spine_section+="

This export was made without \`--parent-repo\`, so its base commit is a **root commit**
and this branch shares no ancestry with \`MiSTer-vX.Y\` in Linux-Kernel_MiSTer. It is a
standalone tree: usable, buildable, and not PR-able, because GitHub's compare API needs a
common ancestor and answers 404 without one (\"No common ancestor\").

To get one, re-run the export with \`--parent-repo <a clone of the fork> --parent <the
newest pristine tarball commit on its spine>\` — for the 6.18 series that is
\`d9ac12a691ead295c8bc6438754767b94c0f26a2\` (\"v6.18.38\").
"
fi

say 'Writing EXPORT.md'
cat >EXPORT.md <<EOF
# This tree is generated

It is a **build output**, not a source of truth. It was rendered from
[Buildroot_MiSTer](https://github.com/mcfbytes/Buildroot_MiSTer) by
\`scripts/export-kernel-tree.sh\`, which is where the kernel is actually maintained.

**Changes made directly to this tree will be erased by the next regeneration.**
To change the kernel, change the patch series in Buildroot_MiSTer and regenerate. There
are two series, and which one a patch belongs in is the first question to answer:

- \`board/mister/de10nano/linux-patches/\` — **carried**. Applied by Buildroot to the
  shipped MiSTer image *and* replayed here. Anything the image needs goes here.
- \`board/mister/de10nano/linux-patches-upstream/\` — **upstream-only**. Replayed here
  and nowhere else; Buildroot never reads this directory. Numbered from 0100 so the
  namespace is obvious from a filename alone.

$upstream_section## What is here

| | |
|---|---|
| Base | Pristine Linux $version from kernel.org, hash-verified (\`$expected\`) |
| Carried patches | $applied commits, one per patch the MiSTer image applies, original authorship preserved |
| Upstream-only patches | $upstream_applied $up_commit_noun, one per patch carried for this tree alone (see above) |
| Config | \`arch/arm/configs/MiSTer_defconfig\` — $config_note |
| DTB build-name alias | 1 commit — \`socfpga_cyclone5_de10_nano.dts\` \`#include\`s the patched \`socfpga_cyclone5_de10nano.dts\` so the .dtb filename Linux-Kernel_MiSTer uses still builds (see below) |
| Vendored drivers | ${#module_doc_rows[@]} commits, one per out-of-tree kernel module vendored here (see below) |
| Tag | \`$tag\` |

The base commit contains no MiSTer change, so the two deltas worth looking at are:

    git diff $tag~$base_offset $tag              # everything MiSTer adds to upstream $version
    git diff $tag~$base_offset $tag~$shipped_offset   # only what the MiSTer image ships

The first is this tree in full: both patch series, the in-tree defconfig, and the
vendored out-of-tree drivers. The second stops at the last carried patch, so it is
precisely the patch set Buildroot applies when it builds the image — no upstream-only
patches, and none of the packaging commits that Buildroot supplies from its own tree
rather than from the kernel source.

## Building standalone

There are **two** documented recipes below, and it is worth being blunt about how they
relate: they compile the same source with the same configuration and differ in exactly
one string — what \`LOCALVERSION\` is set to. That string is not cosmetic (it is the
kernel's own version suffix, so it lands in \`uname -r\`, in the module install path, and
in every module's **vermagic**), but it is the *only* difference. Nothing else about the
kernel, the DTB or the drivers changes between them.

Pick recipe 1 to build a kernel that is interchangeable with the one the MiSTer image in
Buildroot_MiSTer ships. Pick recipe 2 to reproduce the way MiSTer-devel's own releases
are built.

### Recipe 1 — image-compatible (this is what Buildroot builds)

    make ARCH=arm MiSTer_defconfig
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION= \\
        zImage modules intel/socfpga/socfpga_cyclone5_de10nano.dtb
    ./build-mister-modules.sh

Three details on that middle line, each of which will bite you otherwise.

**\`LOCALVERSION=\`** — empty, but set. This tree is a git repo whose HEAD is
$base_offset commits past the \`v$version\` base, so \`scripts/setlocalversion\` correctly
calls the source modified and appends \`+\`, giving \`$version+\`. Buildroot patches a
tarball with no git around it, so the kernel it builds reports plain \`$version\`. That
\`+\` lands in **vermagic**, and vermagic is what the kernel matches on when loading
modules:

    vermagic=$version+ SMP mod_unload ARMv7 p2v8     <- without LOCALVERSION=
    vermagic=$version  SMP mod_unload ARMv7 p2v8     <- Buildroot, and here WITH it

Mismatch it and modprobe rejects every module. With it, modules built here load into the
shipped image's kernel and vice versa. Note that this makes the two **module-compatible**,
not identical: the kernel image built here is not byte-identical to the shipped one
whenever the upstream-only series above is non-empty, because the shipped one does not
contain those patches.

**\`modules\`** — not just \`zImage\`. External modules link against the kernel symbol
table in \`Module.symvers\`, which modpost writes during \`make modules\` (and which needs
\`vmlinux\` first). \`modules_prepare\` does **not** produce it, and without it modpost
calls every kernel symbol undefined
(\`ERROR: modpost: "skb_pull" [8812au.ko] undefined!\`) — which looks like a broken driver
and is not. \`build-mister-modules.sh\` checks for this and says so.

**\`./build-mister-modules.sh\` at all** — the Xbox (xone) and 11ac WiFi drivers are
out-of-tree, so \`zImage\` never builds them.

Building the kernel also needs \`lz4\` on the host, since this config sets
\`CONFIG_KERNEL_LZ4\`.

### Recipe 2 — the stock process (how MiSTer-devel publishes a release)

Same source, same config; \`LOCALVERSION=-MiSTer\` instead of empty, and the two
artifacts a stock release takes from this tree:

    make ARCH=arm MiSTer_defconfig
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION=-MiSTer \\
        zImage modules intel/socfpga/socfpga_cyclone5_de10_nano.dtb

    cat arch/arm/boot/zImage \\
        arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dtb > zImage_dtb

    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION=-MiSTer \\
        INSTALL_MOD_PATH=<staging> modules_install
    tar czf modules.tar.gz -C <staging> ./lib

**Why \`-MiSTer\`, stated as evidence rather than lore.** A stock MiSTer release
(Release 20260907) installs its modules under \`lib/modules/6.18.38-MiSTer/\`, while the
kernel configuration it ships has \`CONFIG_LOCALVERSION=""\` and
\`CONFIG_LOCALVERSION_AUTO\` off. A suffix that is in \`uname -r\` but in neither of those
can only have come from the make command line, so the published kernel is built with
\`LOCALVERSION=-MiSTer\`.

**\`socfpga_cyclone5_de10_nano.dtb\`** — the underscore name, which is the filename
Linux-Kernel_MiSTer has always built. In this tree it is the alias commit described under
*What is here*: it \`#include\`s the patched \`socfpga_cyclone5_de10nano.dts\`, so both
names produce **byte-identical** DTBs. Recipe 1 names the other one only because that is
the string Buildroot passes (\`BR2_LINUX_KERNEL_INTREE_DTS_NAME\`).

**\`cat zImage dtb > zImage_dtb\`** — a plain concatenation, no padding and no
alignment. Stock U-Boot finds the device tree by reading the zImage header's declared-end
field at \`+0x2C\` and adding it to \`\$loadaddr\`, which is true only for an unpadded
\`cat\`. (\`scripts/check-zimage-dtb.sh\` in Buildroot_MiSTer asserts exactly that
contract on a built artifact.)

**\`-C <staging> ./lib\`, with the leading \`./\`** — this is not a stylistic choice.
The MiSTer image creator (\`Linux_Image_creator_MiSTer/create_img.sh\`) unpacks this
tarball with

    tar xfp modules.tar.gz --strip-components=2 -C /media/rootfs/lib

and \`--strip-components\` counts \`.\` as a component. Members named
\`./lib/modules/<ver>/…\` therefore land as \`modules/<ver>/…\` under \`/lib\`, which is
right; members named \`lib/modules/<ver>/…\` (no \`./\`) lose \`lib\` **and** \`modules\`
and land as \`/lib/<ver>/…\`, where modprobe will never find them. Stock's own
\`modules.tar.gz\` is built the first way — every member in it begins \`./lib/\`.

That same script also consumes \`rootfs.tar.bz2\`, \`firmware.tar.gz\` and \`addon.tar\`;
none of those come from this tree. \`zImage_dtb\` is **not** consumed by it either — it is
copied to the SD card's FAT partition as \`linux/zImage_dtb\` and loaded by U-Boot. Of the
release's inputs, this tree produces exactly two: \`zImage_dtb\` and \`modules.tar.gz\`.

### The two recipes, side by side

| | recipe 1 | recipe 2 |
|---|---|---|
| \`LOCALVERSION\` | empty, but set | \`-MiSTer\` |
| \`uname -r\` | \`$version\` | \`$version-MiSTer\` |
| modules install to | \`lib/modules/$version/\` | \`lib/modules/$version-MiSTer/\` |
| vermagic | \`$version …\` | \`$version-MiSTer …\` |
| matches | the Buildroot_MiSTer image | a stock MiSTer-devel release |

Nothing else differs. A module built by one is rejected by the other's kernel — that is
the whole of the incompatibility, and it is a string comparison, not a code difference.

## The two DTB filenames

Linux-Kernel_MiSTer describes this board in its own
\`arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts\` — with the underscore
— and builds the shipped device tree as \`socfpga_cyclone5_de10_nano.dtb\`.

This tree does it the other way round. Mainline gained a DE10-Nano DTS after that branch
was written (\`socfpga_cyclone5_de10nano.dts\`, no underscore, 144616a80889 in v6.14), and
the MiSTer board support here is a **patch on that file** rather than a second copy of
it. That keeps the MiSTer delta a reviewable diff against upstream instead of a ~700-line
vendor file that no one can diff against anything.

The cost of that choice is one filename, so this tree pays it with one file:
\`socfpga_cyclone5_de10_nano.dts\` exists here as a generated alias whose entire body is

    #include "socfpga_cyclone5_de10nano.dts"

plus the matching \`dtb-\$(CONFIG_ARCH_INTEL_SOCFPGA)\` entry next to the existing one. So

    make ARCH=arm ... intel/socfpga/socfpga_cyclone5_de10_nano.dtb
    make ARCH=arm ... intel/socfpga/socfpga_cyclone5_de10nano.dtb

both work and produce **byte-identical** output, because there is only one board
description and both names compile it. \`scripts/check-export-tree.sh\` in
Buildroot_MiSTer builds both and fails if the bytes differ, so the alias cannot quietly
become a second, diverging board.

The MiSTer image does not use the alias: Buildroot builds
\`BR2_LINUX_KERNEL_INTREE_DTS_NAME\`, which names the vanilla file. Like the defconfig
commit, this one is generated by the export and is applied to no image.

## About \`MiSTer_defconfig\`

\`arch/arm/configs/MiSTer_defconfig\` here is the kernel's **minimized** defconfig form.
Linux-Kernel_MiSTer ships the same configuration in the other form — a full resolved
\`.config\`, "Automatically generated file; DO NOT EDIT" header and all, including a
\`CONFIG_CC_VERSION_TEXT\` naming that maintainer's \`arm-none-linux-gnueabihf-gcc\`
(4400 lines on MiSTer-v6.18 @ c129b0fac, against ~500 here).

These are two spellings of one configuration, not two configurations.

    make ARCH=arm MiSTer_defconfig

resolves the file here to the same \`.config\` his full form already spells out, for his
toolchain. The only lines that can differ are the ones kconfig derives from the compiler
in front of it — \`CONFIG_CC_VERSION_TEXT\`, \`CONFIG_GCC_VERSION\`, \`CONFIG_AS_VERSION\`,
\`CONFIG_LD_VERSION\` and the \`CONFIG_CC_HAS_*\` / \`CONFIG_TOOLS_SUPPORT_*\` probes —
which is exactly the machine-pinning the minimized form leaves out. Everything a person
actually decided is identical.

If you want the full form in this tree, generate it; do not hand-write it:

    make ARCH=arm MiSTer_defconfig && cp .config arch/arm/configs/MiSTer_defconfig

## Vendored out-of-tree drivers

| path | pin | build override |
|---|---|---|
$(printf '%s\n' "${module_doc_rows[@]}")

Sources are verbatim upstream at the paths \`MiSTer-v5.15\` uses, so the layout matches.
They are deliberately **not** wired into Kconfig. Their own Makefiles do parse-time work
keyed off \`\$(shell pwd)\`:

    export TopDIR ?= \$(shell pwd)
    \$(shell cp \$(TopDIR)/autoconf_..._linux.h \$(TopDIR)/include/autoconf.h)

In an in-tree build \`pwd\` is the kernel root rather than the module directory, so that
copy lands in the wrong place and the driver's generated \`autoconf.h\` never appears —
silently, because \`\$(shell ...)\` swallows the error. These Makefiles assume they are
always built out-of-tree. \`build-mister-modules.sh\` therefore uses upstream's own
supported out-of-tree path, which is also exactly what Buildroot invokes to build the
shipped image — so it is a proven recipe rather than a workaround.

The pins live in \`package/<name>/<name>.mk\` in Buildroot_MiSTer. Bumping a driver is a
pin change there plus a re-run of the export; nothing here needs rewiring.

Unlike \`MiSTer-v5.15\`, which vendors these in-tree, that means a driver bump does not
touch this tree's history by hand — and the Realtek drivers here track upstreams that
build against 6.18 with **zero** compatibility patches.

$spine_section
What each 5.15 commit became — carried into the image, carried here only (the
upstream-only series above), superseded by an upstream commit (with the vanilla commit
cited), or deliberately dropped — is recorded per commit in
\`MISTER-KERNEL-PATCH-RECON.md\` in Buildroot_MiSTer. No git command can answer that:
across this much context drift \`git patch-id\` matches nothing, so "is this commit in
$version?" is a semantic question, not a mechanical one.

## Publishing

This script never touches a remote. To publish, fetch the orphan branch into a fork
and push from there:

    git -C <your-fork> fetch <this-export-dir> $branch:$branch
    git -C <your-fork> push origin $branch
$(if [[ -n $fork_sync ]]; then cat <<FORKSYNC

## Fork sync point

Reconciled against \`MiSTer-devel/Linux-Kernel_MiSTer\` at commit \`$fork_sync\`.

Commits added to the fork since then have **not** been triaged for backporting:

    git log --oneline $fork_sync..$branch

(in a clone of the FORK, not of this tree — \`$fork_sync\` is a commit of theirs. The
branch name is the fork's own \`$branch\`, which is where this reconciliation was made;
older reconciliations against the 5.15 series read \`MiSTer-v5.15\` there instead.)
FORKSYNC
fi)
EOF

git add EXPORT.md
GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
	git commit --quiet -m "EXPORT.md: state that this tree is generated

Names the source of truth, states that direct edits are erased by the next
regeneration, and records where to look for the disposition of each 5.15 fork
commit.

It also states, with a table, that this tree is the kernel the MiSTer image
ships PLUS the upstream-only patches listed there -- patches Buildroot
deliberately does not apply -- so nothing here claims the two are identical when
they are not. See scripts/export-kernel-tree.sh in Buildroot_MiSTer."

git tag -f "$tag" >/dev/null

# --- 8. Verify what we built, rather than assume it ----------------------------------------

say 'Verifying'
[[ -f arch/arm/configs/MiSTer_defconfig ]] || die 'defconfig missing from the tree'
# shellcheck disable=SC2015 # both sides are pure status checks (no side
# effects to half-apply): die runs iff either `git diff --quiet` reports dirty.
git diff --quiet && git diff --cached --quiet || die 'tree is dirty after export'

# Assert every enabled driver is actually IN the committed tree, rather than trusting that
# the loop above ran. A silent skip here ships a kernel missing WiFi, which is precisely
# the bug this section exists to prevent -- and which a too-strict defconfig parse already
# caused once, vendoring xone alone.
for pkg in "${enabled_kmods[@]}"; do
	if [[ -n ${MODULE_EXPORT_SKIP[$pkg]:-} ]]; then
		printf '  %-52s skipped (%s)\n' "$pkg" "${MODULE_EXPORT_SKIP[$pkg]}"
		continue
	fi
	dest="${MODULE_PATH[$pkg]}"
	git cat-file -e "$tag:$dest" 2>/dev/null ||
		die "$pkg is enabled but $dest is not in the exported tree"
	n="$(git ls-tree -r --name-only "$tag" "$dest" | wc -l)"
	((n > 0)) || die "$pkg vendored at $dest but the directory is empty"
	printf '  %-52s %s files\n' "$dest" "$n"
done
[[ -x build-mister-modules.sh ]] || die 'build-mister-modules.sh missing or not executable'

# Assert the commit offsets EXPORT.md just printed actually resolve to the commits it
# claims they do. This is not paranoia about git: it is a check on OUR arithmetic, which
# has three terms that grow without this file being edited (patch counts, driver count).
# The failure mode it catches is a document that confidently hands upstream reviewers a
# `git diff` range naming the wrong commits -- which nothing else would ever notice,
# because both ranges produce a large, plausible-looking diff either way.
#
# --verify --quiet so an offset that runs off the end of history yields an empty string
# and OUR message, rather than git's "fatal: ambiguous argument" printed first and the
# actionable one scrolled off behind it.
[[ "$(git rev-parse --verify --quiet "$tag~$base_offset^{commit}")" == "$base_commit" ]] ||
	die "EXPORT.md's base offset is wrong: $tag~$base_offset is not the base commit
$base_commit. The 'git diff' one-liners in EXPORT.md would name the wrong range."
[[ "$(git rev-parse --verify --quiet "$tag~$shipped_offset^{commit}")" == "$carried_tip" ]] ||
	die "EXPORT.md's shipped-kernel offset is wrong: $tag~$shipped_offset is not the last
carried patch $carried_tip. The 'only what the MiSTer image ships' diff in EXPORT.md
would include or omit patches."

# Assert every upstream-only patch actually became a commit. Same fail-closed rule as the
# vendored drivers above, and for a sharper reason: nothing else in this repo applies
# these patches at all, so a silent loss here has no second chance to be noticed -- the
# image builds green, the export reports PASS, and upstream simply receives a tree whose
# boot path quietly stopped working. Matching on the subject `git mailinfo` produced means
# this compares what was ASKED FOR against what was COMMITTED, rather than re-counting the
# same array twice.
if ((upstream_applied)); then
	mapfile -t upstream_log < <(git log --format='%s' "$carried_tip..$tag~$upstream_tip_offset")
	for i in "${!upstream_series[@]}"; do
		printf '%s\n' "${upstream_log[@]}" | grep -Fxq -- "${upstream_subjects[$i]}" ||
			die "upstream-only patch $(basename "${upstream_series[$i]}") produced no commit
in the exported tree (no commit with subject: ${upstream_subjects[$i]})"
		printf '  %-52s upstream-only\n' "$(basename "${upstream_series[$i]}")"
	done
fi

# The base must be untouched upstream: our delta may not reach outside the patches.
touched="$(git diff --name-only "$base_commit" "$tag" | wc -l)"

printf '\n'
printf 'RESULT: PASS — exported Linux %s + %s carried patches + %s upstream-only\n' \
	"$version" "$applied" "$upstream_applied"
printf '  tree     %s\n' "$output"
printf '  branch   %s\n' "$branch"
printf '  tag      %s\n' "$tag"
# base_offset + 1, NOT `git rev-list --count HEAD`. The parenthetical enumerates this
# export's own commits, and rev-list counts ANCESTORS too: in --onto/--parent mode that
# silently adds the parent repo's four spine tarball commits, printing 43 against a
# breakdown that sums to 39. A reader who adds it up and comes up short reasonably
# concludes the series got applied twice. base_offset is the distance from the tag back to
# the base (asserted against the real commit above), so it counts everything AFTER the
# base -- hence the +1 to include the base that the "1 base" term names.
#
# module_doc_rows, NOT enabled_kmods, for the same reason: enabled_kmods counts every
# kernel-module package the stack selects, including any named in MODULE_EXPORT_SKIP,
# which produce no commit. module_doc_rows is appended only on the path that actually
# commits, so it is the commit count by construction.
printf '  commits  %s (1 base + %s carried + %s upstream-only + defconfig + dtb alias + %s vendored drivers + build script + EXPORT.md)\n' \
	"$((base_offset + 1))" "$applied" "$upstream_applied" "${#module_doc_rows[@]}"
printf '  files touched vs pristine upstream: %s\n' "$touched"
if ((upstream_applied)); then
	# Said on stdout as well as in EXPORT.md, because this is the one fact about the
	# export that a person running it can get wrong in a way that matters: handing the
	# tree to someone as "the kernel we ship" when it is that plus these.
	printf '  NOTE: this tree is the shipped kernel PLUS %s upstream-only %s from\n' \
		"$upstream_applied" "$up_patch_noun"
	printf '        %s — see EXPORT.md for the table of what and why.\n' "$upstream_patch_dir"
fi
printf '\nPublish with:\n'
printf '  git -C <your-fork> fetch %s %s:%s\n' "$output" "$branch" "$branch"
printf '  git -C <your-fork> push origin %s\n' "$branch"
