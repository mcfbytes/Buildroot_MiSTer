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
# This tree is a git repo whose HEAD sits ~35 commits past the v<ver> base commit, so
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
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- LOCALVERSION= zImage modules
    ./build-mister-modules.sh

Three details on that middle line, each of which will bite you otherwise.

**\`LOCALVERSION=\`** — empty, but set. This tree is a git repo whose HEAD is ~35 commits
past the \`v$version\` base, so \`scripts/setlocalversion\` correctly calls the source
modified and appends \`+\`, giving \`$version+\`. Buildroot builds the same source from a
tarball with no git around it, so its equally-patched kernel reports plain \`$version\`.
That \`+\` lands in **vermagic**, and vermagic is what the kernel matches on when loading
modules:

    vermagic=$version+ SMP mod_unload ARMv7 p2v8     <- without LOCALVERSION=
    vermagic=$version  SMP mod_unload ARMv7 p2v8     <- Buildroot, and here WITH it

Mismatch it and modprobe rejects every module. With it, this tree's kernel and modules
are interchangeable with the shipped image's.

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
