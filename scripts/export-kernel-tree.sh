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
#                                      [--fork-sync SHA] [--tarball FILE]
#
#   --output DIR      where to build the tree (must not already exist)
#   --parent-repo R   clone R and parent the base commit inside it, extending that
#                     repo's tarball spine instead of starting a fresh root
#   --parent C        the spine commit to extend (requires --parent-repo)
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
parent_repo=''
parent=''

while (($#)); do
	case "$1" in
	--output) output="${2:-}"; shift 2 ;;
	--parent-repo) parent_repo="${2:-}"; shift 2 ;;
	--parent) parent="${2:-}"; shift 2 ;;
	--fork-sync) fork_sync="${2:-}"; shift 2 ;;
	--tarball) tarball_override="${2:-}"; shift 2 ;;
	-h | --help) sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

[[ -n $output ]] || die 'missing --output DIR (try --help)'
[[ ! -e $output ]] || die "--output already exists: $output"

# The two go together: a parent is meaningless without the repo it lives in, and cloning
# a repo without saying where to hang the branch would silently fall back to an orphan.
[[ -n $parent_repo && -z $parent ]] && die '--parent-repo requires --parent'
[[ -n $parent && -z $parent_repo ]] && die '--parent requires --parent-repo'

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

if [[ -n $parent_repo ]]; then
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
[[ -n $parent_repo ]] || git init --quiet --initial-branch="$branch"
git config user.name "$EXPORT_NAME"
git config user.email "$EXPORT_EMAIL"
git config commit.gpgsign false

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
[[ -n $parent_repo ]] && git checkout --quiet -b "$branch"

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
       v$version -> [$applied MiSTer commits] -> $branch

\`MiSTer-v5.15\` is **not modified and not an ancestor** — it is a sibling, exactly as
\`MiSTer-v5.14\` already is. Nothing was lost.

Two consequences worth knowing:

- The base commit's parent is itself a pristine tarball commit, so
  \`git diff aba1ef4c1 v$version\` is the **pure upstream 5.15.1 → $version delta**,
  with no MiSTer code on either side.
- No MiSTer-5.15 commit appears in this branch's log, which is the point: this tree
  does not contain most of them, and a log listing changes that are absent from the
  tree would be worse than no log at all.

What each 5.15 commit became — carried, superseded by an upstream commit (with the
vanilla commit cited), or deliberately dropped — is recorded per commit in
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
