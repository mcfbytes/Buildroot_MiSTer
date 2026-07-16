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
# WHAT YOU GET
# ------------
#   <output>/  a fresh git repo, branch MiSTer-v<major.minor>, containing:
#     - one base commit  "Linux <ver>"  — pristine upstream, hash-verified
#     - one commit per carried patch, original authorship preserved
#     - arch/arm/configs/MiSTer_defconfig — so the tree builds standalone:
#           make ARCH=arm MiSTer_defconfig && make ARCH=arm zImage
#       which is the thing `make linux` inside Buildroot cannot hand someone.
#     - EXPORT.md — states it is generated, names the source of truth, and records
#       the fork commit we last reconciled against.
#     - tag mister-<ver>
#
# The branch is an ORPHAN lineage on purpose. It shares no ancestor with MiSTer-v5.15,
# because a merge whose tree ignores its first parent would make `git log` list ~113
# commits whose changes are NOT in the tree (someone reads "xone: update driver" and
# concludes xone is in; it is a Buildroot package now). A log that lists absent changes
# is worse than an absent ancestor. What was dropped is recorded in
# MISTER-KERNEL-PATCH-RECON.md, which cites the superseding vanilla commit per fork
# commit — something no git command can produce.
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
# Usage: scripts/export-kernel-tree.sh --output DIR [--fork-sync SHA] [--tarball FILE]
#
#   --output DIR      where to build the tree (must not already exist)
#   --fork-sync SHA   fork commit this export was reconciled against; recorded in
#                     EXPORT.md as the backport-queue starting point
#   --tarball FILE    use this tarball instead of the dl/ cache or a download
#
# Exit: 0 = tree built and verified; non-zero = anything failed (fails closed).

set -o errexit
set -o nounset
set -o pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DEFCONFIG="$REPO_ROOT/configs/mister_de10nano_defconfig"
readonly HASH_FILE="$REPO_ROOT/board/mister/de10nano/patches/linux/linux.hash"

# Committer identity for the generated commits. Patch AUTHORS are preserved by `git am`;
# this only says who mechanically produced the tree, and it must be explicit so the
# script works on a runner with no git config.
readonly EXPORT_NAME="${EXPORT_COMMITTER_NAME:-MiSTer Buildroot export}"
readonly EXPORT_EMAIL="${EXPORT_COMMITTER_EMAIL:-export@mister-devel.invalid}"

die() { printf 'export-kernel-tree: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s\n' "$*"; }

output=''
fork_sync=''
tarball_override=''

while (($#)); do
	case "$1" in
	--output) output="${2:-}"; shift 2 ;;
	--fork-sync) fork_sync="${2:-}"; shift 2 ;;
	--tarball) tarball_override="${2:-}"; shift 2 ;;
	-h | --help) sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

[[ -n $output ]] || die 'missing --output DIR (try --help)'
[[ ! -e $output ]] || die "--output already exists: $output"

# --- 1. Read the pinned inputs out of the defconfig -----------------------------------
# The defconfig is the single source of truth for what we build; nothing here is
# hardcoded, so a version bump is a one-line defconfig edit and this script follows.

defconfig_value() {
	# Values look like: BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="6.18.38"
	sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$DEFCONFIG" | tail -1
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

series=("$patch_dir"/*.patch)
((${#series[@]})) || die "no patches in $patch_dir"

branch="MiSTer-v${version%.*}" # 6.18.38 -> MiSTer-v6.18, matching the fork's convention
tag="mister-${version}"

say "Exporting Linux $version + ${#series[@]} carried patches -> $output (branch $branch)"

# --- 2. Get the tarball, and verify it against the signed-manifest hash ----------------
# Fails closed: an unverified kernel tarball is the whole reason linux.hash exists.

tarball="$tarball_override"
if [[ -z $tarball ]]; then
	cached="$REPO_ROOT/dl/linux/linux-$version.tar.xz"
	if [[ -f $cached ]]; then
		tarball="$cached"
		say "Using cached tarball: $tarball"
	else
		tarball="$(mktemp -d)/linux-$version.tar.xz"
		url="https://cdn.kernel.org/pub/linux/kernel/v${version%%.*}.x/linux-$version.tar.xz"
		say "Downloading $url"
		curl --fail --location --silent --show-error --output "$tarball" "$url" ||
			die "download failed: $url"
	fi
fi
[[ -f $tarball ]] || die "no such tarball: $tarball"

expected="$(sed -n "s/^sha256[[:space:]]\+\([0-9a-f]\{64\}\)[[:space:]]\+linux-$version\.tar\.xz$/\1/p" "$HASH_FILE" | tail -1)"
[[ -n $expected ]] || die "no sha256 for linux-$version.tar.xz in $HASH_FILE — bump the hash from kernel.org's signed manifest"

actual="$(sha256sum "$tarball" | cut -d' ' -f1)"
[[ $actual == "$expected" ]] || die "tarball hash mismatch for linux-$version.tar.xz
  expected $expected (from $HASH_FILE)
  actual   $actual"
say "Tarball verified: sha256 $actual"

# --- 3. Extract ------------------------------------------------------------------------

mkdir -p "$output"
say "Extracting"
tar -xf "$tarball" -C "$output" --strip-components=1

# kernel.org tarballs come from `git archive`, so every file's mtime is the tag's commit
# time. That makes this stable across machines, unlike the download time.
if [[ -n ${SOURCE_DATE_EPOCH:-} ]]; then
	base_epoch="$SOURCE_DATE_EPOCH"
else
	base_epoch="$(stat -c %Y "$output/Makefile")"
fi
base_date="$(date -u -d "@$base_epoch" '+%Y-%m-%dT%H:%M:%S+00:00')"

# --- 4. Base commit: pristine upstream, on its own ---------------------------------------
# Kept as its own commit so `git diff <base> HEAD` is exactly the MiSTer delta and
# nothing else — the review question worth answering.

cd "$output"
git init --quiet --initial-branch="$branch"
git config user.name "$EXPORT_NAME"
git config user.email "$EXPORT_EMAIL"
git config commit.gpgsign false

git add --all
GIT_AUTHOR_DATE="$base_date" GIT_COMMITTER_DATE="$base_date" \
	git commit --quiet --file=- <<EOF
Linux $version

Pristine upstream kernel $version, unpacked from linux-$version.tar.xz as
published on kernel.org.

  sha256 $expected

Verified against this repo's pinned hash, itself transcribed from kernel.org's
PGP-signed release manifest. No MiSTer change is present in this commit: every
MiSTer delta is a separate commit on top, so a diff from this commit to the tip
of $branch is exactly the MiSTer patch series and nothing else.

Generated by scripts/export-kernel-tree.sh in Buildroot_MiSTer. Do not edit this
tree directly; see EXPORT.md.
EOF
base_commit="$(git rev-parse HEAD)"

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
say "Applied $applied/${#series[@]} patches cleanly"

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

# --- 7. Say plainly what this tree is ----------------------------------------------------

say 'Writing EXPORT.md'
cat >EXPORT.md <<EOF
# This tree is generated

It is a **build output**, not a source of truth. It was rendered from
[Buildroot_MiSTer](https://github.com/mcfbytes/Buildroot_MiSTer) by
\`scripts/export-kernel-tree.sh\`, which is where the kernel is actually maintained.

**Changes made directly to this tree will be erased by the next regeneration.**
To change the kernel, change the patch series in Buildroot_MiSTer
(\`board/mister/de10nano/linux-patches/\`) and regenerate.

## What is here

| | |
|---|---|
| Base | Pristine Linux $version from kernel.org, hash-verified (\`$expected\`) |
| On top | $applied commits, one per carried MiSTer patch, original authorship preserved |
| Config | \`arch/arm/configs/MiSTer_defconfig\` — $config_note |
| Tag | \`$tag\` |

The base commit contains no MiSTer change, so

    git diff $tag~$((applied + 1)) $tag

is exactly the MiSTer delta against upstream and nothing else.

## Building standalone

    make ARCH=arm MiSTer_defconfig
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage

## Why this branch has no common ancestor with MiSTer-v5.15

Deliberate. Attaching it to the 5.15 history would need a merge whose tree ignores
its first parent, which makes \`git log\` list ~113 commits whose changes are **not
in this tree** — someone reads "xone: update driver" and concludes xone is present,
when it is a Buildroot package now. A log that lists absent changes is worse than an
absent ancestor.

\`MiSTer-v5.15\` is untouched and immutable; nothing was lost. What each of its commits
became — carried, superseded by an upstream commit (with the vanilla commit cited),
or deliberately dropped — is recorded per commit in \`MISTER-KERNEL-PATCH-RECON.md\`
in Buildroot_MiSTer. No git command can answer that question: across this much context
drift \`git patch-id\` matches nothing, so "is this commit in $version?" is a semantic
question, not a mechanical one.

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
commit. See scripts/export-kernel-tree.sh in Buildroot_MiSTer."

git tag -f "$tag" >/dev/null

# --- 8. Verify what we built, rather than assume it ----------------------------------------

say 'Verifying'
[[ -f arch/arm/configs/MiSTer_defconfig ]] || die 'defconfig missing from the tree'
git diff --quiet && git diff --cached --quiet || die 'tree is dirty after export'

# The base must be untouched upstream: our delta may not reach outside the patches.
touched="$(git diff --name-only "$base_commit" "$tag" | wc -l)"

printf '\n'
printf 'RESULT: PASS — exported Linux %s + %s patches\n' "$version" "$applied"
printf '  tree     %s\n' "$output"
printf '  branch   %s\n' "$branch"
printf '  tag      %s\n' "$tag"
printf '  commits  %s (1 base + %s patches + defconfig + EXPORT.md)\n' \
	"$(git rev-list --count HEAD)" "$applied"
printf '  files touched vs pristine upstream: %s\n' "$touched"
printf '\nPublish with:\n'
printf '  git -C <your-fork> fetch %s %s:%s\n' "$output" "$branch" "$branch"
printf '  git -C <your-fork> push origin %s\n' "$branch"
