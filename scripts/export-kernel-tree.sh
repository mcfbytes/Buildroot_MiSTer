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
#
# — and each MiSTer-vX.Y branch hangs off a spine point with the MiSTer series replayed
# on top (MiSTer-v5.15 = aba1ef4c1 + 112 commits). Every spine commit is a PRISTINE
# tarball with no MiSTer code in it.
#
# So the right shape for a new kernel is to extend the spine the same way, parenting the
# base commit on the newest spine point (aba1ef4c1) rather than on a branch tip:
#
#   aba1ef4c1 v5.15.1 --+-- [112 MiSTer commits] --> MiSTer-v5.15   (theirs, untouched)
#                       |
#                       +-- v6.18.38 -- [our commits] -> MiSTer-v6.18
#
# That buys three things at once:
#   - shared ancestry with MiSTer-v5.15, so GitHub can compare and a PR is possible at
#     all (across unrelated histories the compare API 404s: "No common ancestor");
#   - a log with NO MiSTer-5.15 commits in it — they are siblings, not ancestors — so
#     nothing lists a change that is absent from the tree. Parenting on the branch TIP
#     instead would list ~112 commits whose changes this tree discards, and a reader
#     would see "xone: update driver" and conclude xone is present when it is a
#     Buildroot package now;
#   - a base commit whose diff against its parent is PURE upstream 5.15.1 -> 6.18.38,
#     with zero MiSTer noise, because both trees are pristine.
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
#                     from the pinned tarball (requires --parent-repo)
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
readonly DEFCONFIG="$REPO_ROOT/configs/mister_de10nano_defconfig"
readonly HASH_FILE="$REPO_ROOT/board/mister/de10nano/patches/linux/linux.hash"

# Committer identity for the generated commits. Patch AUTHORS are preserved by `git am`;
# this only says who mechanically produced the tree, and it must be explicit so the
# script works on a runner with no git config.
readonly EXPORT_NAME="${EXPORT_COMMITTER_NAME:-MiSTer Buildroot export}"
readonly EXPORT_EMAIL="${EXPORT_COMMITTER_EMAIL:-export@mister-devel.invalid}"

die() { printf 'export-kernel-tree: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s\n' "$*"; }

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

# --- 1. Read the pinned inputs out of the defconfig -----------------------------------
# The defconfig is the single source of truth for what we build; nothing here is
# hardcoded, so a version bump is a one-line defconfig edit and this script follows.

defconfig_value() {
	# Values look like: BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.38"
	#
	# Do NOT anchor on the closing quote. This defconfig carries trailing comments on
	# some lines, and anchoring silently yields an empty value rather than failing --
	# which for an optional setting (a config fragment) would mean quietly dropping it.
	sed -n "s/^$1=\"\([^\"]*\)\".*$/\1/p" "$DEFCONFIG" | tail -1
}

# Buildroot spells the external tree's own path as a make variable inside the defconfig;
# resolve it the way Buildroot would.
resolve_br_path() {
	printf '%s' "${1//\$(BR2_EXTERNAL_MISTER_PATH)/$REPO_ROOT}"
}

[[ -f $DEFCONFIG ]] || die "no defconfig at $DEFCONFIG"

version="$(defconfig_value BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE)"
[[ -n $version ]] || die 'BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE not set in defconfig'

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

Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer.
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
declare -A MODULE_PATH=(
	[xone]='drivers/hid/xone'
	[rtl8812au]='drivers/net/wireless/realtek/rtl8812au'
	[rtl8814au-morrownr]='drivers/net/wireless/realtek/rtl8814au'
	[rtl8821au-morrownr]='drivers/net/wireless/realtek/rtl8821au'
	[rtl8821cu-morrownr]='drivers/net/wireless/realtek/rtl8821cu'
	[rtl88x2bu]='drivers/net/wireless/realtek/rtl88x2bu'
	[rtl8188eu-aircrack-ng]='drivers/net/wireless/realtek/rtl8188eu'
	[rtl8188fu]='drivers/net/wireless/realtek/rtl8188fu'
)

# A package is a kernel module iff its .mk evals Buildroot's kernel-module infra. Detected
# rather than listed, so a new one cannot be missed by forgetting to update a list here.
#
# The `=y` is NOT anchored to end-of-line: this defconfig annotates most package lines
# with a trailing comment ("BR2_PACKAGE_RTL8812AU=y    # RTL8812AU 11ac -- ..."), and
# anchoring matched only the one line without one, silently vendoring xone alone and
# dropping all three WiFi drivers.
mapfile -t enabled_kmods < <(
	sed -n 's/^\(BR2_PACKAGE_[A-Z0-9_]*\)=y\([[:space:]].*\)\?$/\1/p' "$DEFCONFIG" |
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

((${#enabled_kmods[@]})) || die 'detected zero kernel-module packages in the defconfig.
That is almost certainly a parsing bug in this script rather than the truth — the image
ships xone and the Realtek WiFi drivers. Refusing to export a tree missing them.'

say "Vendoring ${#enabled_kmods[@]} out-of-tree kernel modules: ${enabled_kmods[*]}"
module_build_lines=()
module_doc_rows=()

for pkg in "${enabled_kmods[@]}"; do
	upper="$(tr 'a-z-' 'A-Z_' <<<"$pkg")"
	mk="$REPO_ROOT/package/$pkg/$pkg.mk"
	dest="${MODULE_PATH[$pkg]:-}"

	# Fail closed. Silently skipping an enabled driver is exactly the regression this
	# whole section exists to prevent.
	[[ -n $dest ]] || die "no in-tree path mapped for kernel-module package '$pkg'.
Add it to MODULE_PATH in $(basename "${BASH_SOURCE[0]}") — refusing to export a tree
that silently omits a driver the image ships."

	pkg_version="$(sed -n "s/^${upper}_VERSION = //p" "$mk" | tail -1)"
	[[ -n $pkg_version ]] || die "no ${upper}_VERSION in $mk"
	pkg_opts="$(sed -n "s/^${upper}_MODULE_MAKE_OPTS = //p" "$mk" | tail -1)"

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
#     carried patches + upstream-only patches + defconfig + one per vendored driver
#     + build-mister-modules.sh + EXPORT.md
#
# and three of those terms grow on their own -- a new kernel-module package changes it
# without anyone touching this section. So it is MEASURED, not derived from a formula
# that has to be kept in sync. (The previous hand-derived `$((applied + 1))` was already
# wrong before the upstream-only series existed: with 31 carried patches it named a
# mid-series commit rather than the base, because it counted neither the defconfig, the
# three driver commits, the build script, nor EXPORT.md itself.)
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
| Vendored drivers | ${#enabled_kmods[@]} commits, one per out-of-tree kernel module (see below) |
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

    make ARCH=arm MiSTer_defconfig
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION= zImage modules
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

**The third line at all** — the Xbox (xone) and 11ac WiFi drivers are out-of-tree, so
\`zImage\` never builds them.

Building the kernel also needs \`lz4\` on the host, since this config sets
\`CONFIG_KERNEL_LZ4\`.

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

## Where this branch hangs

This repo's tarball commits form a spine, and each \`MiSTer-vX.Y\` branch hangs off a
spine point with the MiSTer series replayed on top. This branch extends that spine the
same way, so it is the next entry rather than a foreign import:

    e12ed6c19 v5.13.12 -> 137491a75 v5.14 -> b6f2ca1c4 v5.14.5 -> aba1ef4c1 v5.15.1
                                                                       |
                                          +----------------------------+
                                          |
       [112 MiSTer commits] -> MiSTer-v5.15        (untouched)
                                          |
       v$version -> [$applied carried + $upstream_applied upstream-only] -> $branch

\`MiSTer-v5.15\` is **not modified and not an ancestor** — it is a sibling, exactly as
\`MiSTer-v5.14\` already is. Nothing was lost.

Two consequences worth knowing:

- The base commit's parent is itself a pristine tarball commit, so
  \`git diff aba1ef4c1 v$version\` is the **pure upstream 5.15.1 → $version delta**,
  with no MiSTer code on either side.
- No MiSTer-5.15 commit appears in this branch's log, which is the point: this tree
  does not contain most of them, and a log listing changes that are absent from the
  tree would be worse than no log at all.

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

    git log --oneline $fork_sync..MiSTer-v5.15
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
printf '  commits  %s (1 base + %s carried + %s upstream-only + defconfig + %s vendored drivers + build script + EXPORT.md)\n' \
	"$((base_offset + 1))" "$applied" "$upstream_applied" "${#enabled_kmods[@]}"
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
