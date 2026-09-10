#!/usr/bin/env bash
#
# check-export-tree.sh — prove that the tree scripts/export-kernel-tree.sh renders is the
# kernel Buildroot builds, and that it builds with the commands upstream actually uses.
#
# WHY THIS EXISTS
# ---------------
# scripts/export-kernel-tree.sh renders {pinned tarball + ordered patch series} into a git
# tree for MiSTer-devel/Linux-Kernel_MiSTer. That export verifies its own INTERNAL
# consistency — every patch became a commit, every enabled driver is present, the offsets
# EXPORT.md prints resolve to the commits it claims. What it cannot check, because it
# never sees one, is the thing the export is FOR:
#
#   1. that the tree it produced is byte-for-byte the source Buildroot compiles, so the
#      claim "this is the kernel the MiSTer image ships" is a fact and not a hope; and
#   2. that the tree BUILDS with the commands the maintainer of Linux-Kernel_MiSTer runs
#      on his own branch — in particular
#      `make intel/socfpga/socfpga_cyclone5_de10_nano.dtb`, the underscore filename his
#      Makefile has always carried, which our tree only has because the export generates
#      an alias for it.
#
# Both failures are silent in every other check this repo has. A patch applied by
# Buildroot but dropped from the export (or vice versa) produces a green image build, a
# green export, and a published tree that quietly is not what anyone thinks it is. So
# this script exists to make the reproducibility claim testable rather than asserted.
#
# WHAT IT ASSERTS
# ---------------
#   (1) IDENTITY. --export DIR really is an export: it has the tag mister-<ver>, an
#       EXPORT.md, and the commit layout the export produces (a pristine `v<ver>` base,
#       the carried series, the generated defconfig / DTB-alias / build-script / EXPORT.md
#       commits). <ver> must equal the version this repo pins, or the two trees being
#       compared are different kernels and every later result is meaningless.
#
#   (2) SAMENESS (--build-dir). The export's CARRIED TIP — the commit just before the
#       upstream-only series, i.e. base + exactly the patches Buildroot applies — must be
#       byte-identical to Buildroot's patched kernel source, ignoring build outputs. Any
#       difference is a FAIL with the file list. This is the reproducibility proof.
#
#       The carried tip is DERIVED, never hardcoded: the offsets come out of the
#       export's own EXPORT.md (the same `git diff mister-<ver>~N` one-liners it publishes
#       for reviewers) and are then cross-checked against the number of patch files in
#       this repo's carried series. Hardcoding a count would silently rot the first time
#       a patch was added — and it would rot into a PASS, because a short range still
#       diffs cleanly against a build dir that happens to match the shorter prefix.
#
#   (2b) CONFIG. Buildroot's resolved .config vs `make ARCH=arm MiSTer_defconfig` run
#       against the export. Differences in the symbols kconfig derives from the compiler
#       in front of it (CONFIG_CC_VERSION_TEXT, CONFIG_GCC_VERSION, the CONFIG_CC_HAS_*
#       probes, ...) are EXPECTED whenever the two builds used different toolchains, and
#       are printed separately from real ones rather than being hidden — hiding them
#       would also hide a real difference that happened to share a prefix.
#
#   (3) BUILDABILITY. zImage plus BOTH DTB names:
#       intel/socfpga/socfpga_cyclone5_de10_nano.dtb (the generated alias, the name
#       MiSTer-v5.15 builds) and intel/socfpga/socfpga_cyclone5_de10nano.dtb (the vanilla
#       name, which is what BR2_LINUX_KERNEL_INTREE_DTS_NAME makes Buildroot build). Their
#       output must be BYTE-IDENTICAL: the alias is a one-line #include of the patched
#       vanilla DTS, so anything else means it has drifted into a second board
#       description, which is exactly the failure a filename alias invites.
#
# WHAT IT DOES NOT DO
# -------------------
# It never writes into --export or --build-dir. The kernel builds go through `make O=`
# into a scratch directory, which is also why no copy of the export is made: `make O=`
# leaves the source tree untouched by construction, and copying ~1.4GB to get the same
# property would be slower and less certain. The export's cleanliness is asserted
# afterwards rather than assumed.
#
# Usage: scripts/check-export-tree.sh --export DIR [--build-dir DIR]
#                                     [--cross-compile PREFIX | --llvm] [--no-build]
#
#   --export DIR        the tree scripts/export-kernel-tree.sh produced (required)
#   --build-dir DIR     Buildroot's patched kernel source, normally
#                       output/build/linux-<ver>. Enables checks (2) and (2b). Without
#                       it the sameness proof is SKIPPED and said so — it is not a pass.
#   --cross-compile PFX cross-compiler prefix for the builds, e.g.
#                       arm-linux-gnueabihf-. Also used for the .config comparison, so
#                       that CONFIG_CC_VERSION_TEXT and friends are produced by the same
#                       compiler Buildroot used and the diff is about configuration.
#   --llvm              build with LLVM=1 (clang/lld) instead of a GCC cross prefix.
#                       Mutually exclusive with --cross-compile.
#   --no-build          skip check (3). Fast structural + sameness run.
#
# Exit: 0 = every check that ran passed; 1 = at least one failed; 2 = usage/IO error.

set -o errexit
set -o nounset
set -o pipefail
export LC_ALL=C

# Assigned then marked readonly separately: `readonly X="$(cmd)"` masks cmd's exit status
# (shellcheck SC2155), and the rest of scripts/ avoids that pattern.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
ROOT="$REPO_ROOT"
readonly ROOT
# shellcheck source=scripts/lib/config-stacks.sh
. "$REPO_ROOT/scripts/lib/config-stacks.sh"

# The same stack scripts/export-kernel-tree.sh exports, for the same reason: since the
# 2026-09 fragment split no single fragment holds both the kernel pin and the package
# selections, and reading one file gives a confidently wrong answer. See that script's
# STACK_FILES note.
readonly CHECK_STACK=DE10NANO

readonly ALIAS_DTB='intel/socfpga/socfpga_cyclone5_de10_nano.dtb'
readonly VANILLA_DTB='intel/socfpga/socfpga_cyclone5_de10nano.dtb'
readonly ALIAS_DTS='arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10_nano.dts'
readonly VANILLA_DTS='arch/arm/boot/dts/intel/socfpga/socfpga_cyclone5_de10nano.dts'

prog="${0##*/}"
readonly prog

usage() { sed -n '/^# Usage:/,/^# Exit:/{p;/^# Exit:/q;}' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; }
die()   { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }
say()   { printf '\n=== %s\n' "$*"; }
ok()    { printf 'ok   %s\n' "$*"; passes=$((passes + 1)); }
bad()   { printf 'FAIL %s\n' "$*" >&2; fails=$((fails + 1)); }
skip()  { printf 'skip %s\n' "$*"; skips=$((skips + 1)); }
note()  { printf '       %s\n' "$*"; }

passes=0
fails=0
skips=0

scratch=''
cleanup() {
	# `if`, not `[[ ... ]] && rm`: as an EXIT trap this function's own status becomes the
	# script's, and a false test would turn a clean run into exit 1. Same shape as
	# scripts/export-kernel-tree.sh's cleanup().
	if [[ -n $scratch ]]; then
		rm -rf "$scratch"
	fi
}
trap cleanup EXIT

export_dir=''
build_dir=''
cross_compile=''
use_llvm=false
do_build=true

while (($#)); do
	case "$1" in
	--export) export_dir="${2:-}"; shift 2 ;;
	--build-dir) build_dir="${2:-}"; shift 2 ;;
	--cross-compile) cross_compile="${2:-}"; shift 2 ;;
	--llvm) use_llvm=true; shift ;;
	--no-build) do_build=false; shift ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; die "unknown argument: $1" ;;
	esac
done

[[ -n $export_dir ]] || { usage >&2; die 'missing --export DIR'; }
[[ -d $export_dir ]] || die "no such directory: $export_dir"
# Both a prefix and LLVM=1 would mean two different compilers for one build, and kbuild
# resolves that in a way nobody should have to remember.
[[ -n $cross_compile ]] && $use_llvm &&
	die '--cross-compile and --llvm are mutually exclusive.'

export_dir="$(cd "$export_dir" && pwd)"
[[ -z $build_dir ]] || {
	[[ -d $build_dir ]] || die "no such directory: $build_dir"
	build_dir="$(cd "$build_dir" && pwd)"
}

scratch="$(mktemp -d "${TMPDIR:-/tmp}/check-export-tree.XXXXXX")" ||
	die 'could not create a temporary directory'

# make flags shared by every invocation below, so the .config comparison and the build
# cannot accidentally use different toolchains.
make_flags=(ARCH=arm)
$use_llvm && make_flags+=(LLVM=1)
[[ -z $cross_compile ]] || make_flags+=("CROSS_COMPILE=$cross_compile")

# --- 1. Identity: is this an export, and is it OUR export? ----------------------------

say 'Export identity'

git -C "$export_dir" rev-parse --git-dir >/dev/null 2>&1 ||
	die "$export_dir is not a git repository — scripts/export-kernel-tree.sh produces one."

# mapfile, not an unquoted $(...): word-splitting a path list is a bug waiting for the
# first directory with a space in it, and shellcheck flags it (SC2046).
mapfile -t stack_files < <(config_stack_files "$CHECK_STACK")
((${#stack_files[@]})) ||
	die "no ${CHECK_STACK}_FRAGMENTS line in $REPO_ROOT/configs/fragments/stacks.mk"

# All stack files in merge order, `tail -1` last: kconfig's own last-definition-wins rule,
# so a symbol moved between fragments still resolves to the value the image is built with.
pinned_version="$(sed -n 's/^BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE="\([^"]*\)".*$/\1/p' \
	"${stack_files[@]}" | tail -1)"
[[ -n $pinned_version ]] ||
	die "BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE not set in the $(config_stack_label "$CHECK_STACK") stack"

tag="mister-$pinned_version"
git -C "$export_dir" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null ||
	bad "no tag $tag in $export_dir — either this is not an export, or it was made from a
       different kernel pin than this repo's ($pinned_version). Everything below compares
       two trees; comparing two different kernels would produce a long, meaningless diff."
((fails == 0)) || { printf '\nRESULT: FAIL — %s is not an export of Linux %s.\n' \
	"$export_dir" "$pinned_version" >&2; exit 1; }
ok "tag $tag present, matching the repo pin ($pinned_version)"

# EXPORT.md is where the offsets come from, so it is not optional decoration here.
git -C "$export_dir" cat-file -e "$tag:EXPORT.md" 2>/dev/null ||
	die "no EXPORT.md at $tag — this script derives the commit layout from the
\`git diff\` one-liners EXPORT.md publishes, so it cannot proceed without it."
export_md="$scratch/EXPORT.md"
git -C "$export_dir" show "$tag:EXPORT.md" >"$export_md"

# THE OFFSETS ARE READ, NOT COUNTED.
#
# EXPORT.md publishes exactly two ranges, and they are the export's own arithmetic:
#
#     git diff <tag>~<base_offset> <tag>              # everything MiSTer adds
#     git diff <tag>~<base_offset> <tag>~<shipped_offset>   # only what the image ships
#
# Reading them here means this check and the document upstream reviewers use cannot
# disagree: if the offsets are wrong, they are wrong in both places and this script says
# so, rather than quietly checking a range no reviewer will ever look at. The alternative
# — counting commits back from the tag — would need a hardcoded number of generated
# commits (defconfig + DTB alias + one per vendored driver + build script + EXPORT.md),
# which is precisely the thing that grows on its own.
#
# The first pattern requires whitespace-then-# after the tag so it cannot also match the
# second line, whose tag is followed by `~`.
base_offset="$(sed -n "s|^[[:space:]]*git diff $tag~\([0-9]\{1,\}\) $tag[[:space:]]\{1,\}#.*|\1|p" \
	"$export_md" | head -1)"
shipped_offset="$(sed -n "s|^[[:space:]]*git diff $tag~[0-9]\{1,\} $tag~\([0-9]\{1,\}\).*|\1|p" \
	"$export_md" | head -1)"
[[ -n $base_offset && -n $shipped_offset ]] ||
	die "could not read the commit offsets out of EXPORT.md ($tag:EXPORT.md).
This script expects the two \`git diff $tag~N ...\` lines that
scripts/export-kernel-tree.sh writes in its 'What is here' section. If that wording
changed, change this reader with it — do not hardcode a count here."

base_commit="$(git -C "$export_dir" rev-parse --verify --quiet "$tag~$base_offset^{commit}")" ||
	bad "EXPORT.md names $tag~$base_offset as the base, which is not a commit"
carried_tip="$(git -C "$export_dir" rev-parse --verify --quiet "$tag~$shipped_offset^{commit}")" ||
	bad "EXPORT.md names $tag~$shipped_offset as the last carried patch, which is not a commit"

if [[ -n ${base_commit:-} && -n ${carried_tip:-} ]]; then
	base_subject="$(git -C "$export_dir" log --format=%s -1 "$base_commit")"
	if [[ $base_subject == "v$pinned_version" ]]; then
		ok "base commit $(git -C "$export_dir" rev-parse --short "$base_commit") is \"v$pinned_version\" (pristine upstream)"
	else
		bad "EXPORT.md's base offset names a commit whose subject is \"$base_subject\",
       not \"v$pinned_version\". The published \`git diff\` ranges name the wrong commits."
	fi

	# Cross-check the offsets against the series this repo actually carries. This is the
	# half that catches an EXPORT.md whose two offsets are internally consistent but were
	# computed from a different series than the one on disk — which is what a stale export
	# is.
	patch_dir="$(sed -n 's/^BR2_LINUX_KERNEL_PATCH="\([^"]*\)".*$/\1/p' \
		"${stack_files[@]}" | tail -1)"
	patch_dir="${patch_dir//\$(BR2_EXTERNAL_MISTER_PATH)/$REPO_ROOT}"
	shopt -s nullglob
	carried_patches=("$patch_dir"/*.patch)
	shopt -u nullglob
	carried_commits="$(git -C "$export_dir" rev-list --count "$base_commit..$carried_tip")"
	if ((carried_commits == ${#carried_patches[@]})); then
		ok "carried block is $carried_commits commits, one per patch in $(basename "$patch_dir")/"
	else
		bad "carried block is $carried_commits commits but $patch_dir
       holds ${#carried_patches[@]} patches. The export is stale, or its offsets are wrong;
       either way the tree below is not the series this repo carries."
	fi
fi

# The generated commits, by subject. Named individually rather than counted, because the
# failure worth catching is a specific one going missing — the DTB alias in particular,
# whose absence makes the maintainer's own build command fail on a tree that otherwise
# looks complete.
#
# The subjects are collected into a FILE first, and every grep below reads that file
# rather than a pipe from git. `set -o pipefail` plus `grep -q` is a trap here: grep exits
# at the first match and closes the pipe, git dies of SIGPIPE with status 141, and
# pipefail hands the pipeline THAT status -- so `if git log ... | grep -q` reports "not
# found" for a subject that is present. Observed, not theorized: this check failed all
# three of its own commits that way.
git -C "$export_dir" log --format=%s "$tag" >"$scratch/subjects"

for subject in \
	'ARM: configs: add MiSTer_defconfig' \
	'ARM: dts: socfpga: add socfpga_cyclone5_de10_nano.dts build-name alias' \
	'build-mister-modules.sh: build the vendored out-of-tree drivers'; do
	if grep -Fxq -- "$subject" "$scratch/subjects"; then
		ok "generated commit present: $subject"
	else
		bad "no generated commit \"$subject\" in $tag"
	fi
done

for f in EXPORT.md build-mister-modules.sh arch/arm/configs/MiSTer_defconfig \
	"$ALIAS_DTS" "$VANILLA_DTS"; do
	if git -C "$export_dir" cat-file -e "$tag:$f" 2>/dev/null; then
		ok "in the tree at $tag: $f"
	else
		bad "missing from the tree at $tag: $f"
	fi
done

# The alias must be an alias. A DTS of that name containing real board content would
# build a DTB that differs from the shipped one, which is the whole failure mode the
# generated commit exists to avoid; check (3) proves the bytes match, this proves the
# INTENT (and still says something useful under --no-build).
if git -C "$export_dir" cat-file -e "$tag:$ALIAS_DTS" 2>/dev/null; then
	# Same SIGPIPE/pipefail trap as above: materialize, then grep.
	git -C "$export_dir" show "$tag:$ALIAS_DTS" >"$scratch/alias.dts"
	if grep -q "^#include \"$(basename "$VANILLA_DTS")\"$" "$scratch/alias.dts"; then
		ok "$(basename "$ALIAS_DTS") #includes $(basename "$VANILLA_DTS")"
	else
		bad "$(basename "$ALIAS_DTS") does not #include $(basename "$VANILLA_DTS") —
       it is a second board description, not a build-name alias."
	fi
fi

# --- 2. Sameness: the carried tip vs Buildroot's patched source ------------------------
#
# WHAT IS IGNORED, AND WHY IT IS A LIST RATHER THAN "ignore anything untracked"
# ----------------------------------------------------------------------------
# --build-dir is Buildroot's kernel BUILD directory: the patched source and the objects
# built from it, in one tree. Everything kbuild writes there has to come out of the
# comparison or every run is a wall of noise. But the exclusion must be a NAMED list,
# because the interesting failure — a file Buildroot's series adds that the export's does
# not — also appears as "a file only one side has", and a blanket rule would swallow it.
readonly -a IGNORE_GLOBS=(
	'.config' '.config.old' '.config.cmd' '.version' '.gitattributes.orig'
	'.missing-syscalls.d' '.thinlto-cache/*' '.tmp_*' '*/.tmp_*'
	'Module.symvers' 'modules.order' 'modules.builtin' 'modules.builtin.*'
	'System.map' 'vmlinux' 'vmlinux.*' 'vmlinuz*'
	'*.o' '*.o.*' '*.ko' '*.mod' '*.mod.c' '*.mod.o' '*.a' '*.cmd' '*.d'
	'*.symtypes' '*.tmp' '*.orig' '*.rej' '*.dtb' '*.dtbo' '*.dtb.S' '*.i' '*.lst'
	'include/generated/*' 'include/config/*' '*/include/generated/*'
	'arch/arm/boot/*'
	'.stamp_*' '.applied_patches_list' '.files-list*.txt'
	'certs/x509.genkey' 'usr/initramfs_data.cpio*' 'usr/gen_init_cpio'
	'.git/*' 'EXPORT.md' 'build-mister-modules.sh'
	'arch/arm/configs/MiSTer_defconfig'
	# Generated files that LOOK like source, which is why they need naming here: the
	# SOURCE_RE rule below would otherwise call each of them real drift. flex and bison
	# write the first three into the source tree (scripts/kconfig, scripts/genksyms,
	# scripts/dtc), and the rest are written by the build's own generators. Every one was
	# seen for real in a Buildroot kernel build directory.
	'*.lex.c' '*.tab.c' '*.tab.h'
	'scripts/mod/devicetable-offsets.h' 'scripts/mod/elfconfig.h'
	'security/selinux/flask.h' 'security/selinux/av_permissions.h'
	'drivers/tty/vt/consolemap_deftbl.c' 'drivers/tty/vt/defkeymap.c'
	'lib/crc32table.h' 'lib/crc64table.h' 'lib/oid_registry_data.c'
	'kernel/config_data*' 'kernel/kheaders_data*' '.kernelrelease'
	'*.export.c' '*.lds' '*.dt.yaml' '*.dtb.S' '*.s'
)

# A path that is only in --build-dir and is not matched above is reported. Most such
# paths are host tools kbuild compiles in place (scripts/basic/fixdep, scripts/kallsyms,
# scripts/dtc/dtc, ...) — real build outputs with no extension to match on. They are
# classified by LOCATION, and only for the build-dir-only direction: a path under one of
# these that is missing from the export is a build artifact, while a path anywhere else,
# or any missing/differing file in the other direction, is a real difference.
readonly -a ARTIFACT_DIRS=(scripts/ tools/ certs/ usr/ security/selinux/ security/apparmor/ .thinlto-cache/)
# ... except when it looks like SOURCE. A .c/.h/Makefile/Kconfig under scripts/ that only
# Buildroot has is exactly the drift this check is for, and "it lives under scripts/" must
# not be allowed to excuse it.
readonly SOURCE_RE='\.(c|h|S|dts|dtsi|rs|sh|pl|py|awk|json|yaml|rst)$|(^|/)(Makefile|Kbuild|Kconfig)[^/]*$'

path_ignored() {
	local p="$1" g
	for g in "${IGNORE_GLOBS[@]}"; do
		# shellcheck disable=SC2053 # unquoted RHS is the POINT: glob match, not string ==
		[[ $p == $g ]] && return 0
	done
	return 1
}

say 'Sameness: export carried tip vs Buildroot build dir'

if [[ -z $build_dir ]]; then
	skip 'tree comparison — no --build-dir given (this is NOT a pass; the
       reproducibility claim is unproven without Buildroot'"'"'s patched source)'
	skip 'config comparison — no --build-dir given'
elif [[ -z ${carried_tip:-} ]]; then
	skip 'tree comparison — the carried tip could not be resolved (see above)'
	skip 'config comparison — the carried tip could not be resolved'
else
	# The export side: path + blob sha + mode, straight out of git. No extraction, so no
	# 1.4GB copy and no chance of the copy itself introducing a difference.
	git -C "$export_dir" ls-tree -r "$carried_tip" |
		awk -F'\t' '{ split($1, a, " "); print $2 "\t" a[1] "\t" a[3] }' |
		while IFS=$'\t' read -r path mode sha; do
			path_ignored "$path" || printf '%s\t%s\t%s\n' "$path" "$mode" "$sha"
		done | sort >"$scratch/export.tsv"

	# The build side: every regular file and symlink, relative, minus the ignore list.
	# -printf is GNU find; this repo's scripts already require GNU coreutils behaviour
	# (stat -c in export-kernel-tree.sh), so that is not a new constraint.
	(cd "$build_dir" && find . \( -type f -o -type l \) -printf '%P\n') |
		while IFS= read -r path; do
			path_ignored "$path" || printf '%s\n' "$path"
		done | sort >"$scratch/build.paths"

	cut -f1 "$scratch/export.tsv" >"$scratch/export.paths"

	comm -23 "$scratch/export.paths" "$scratch/build.paths" >"$scratch/only-export"
	comm -13 "$scratch/export.paths" "$scratch/build.paths" >"$scratch/only-build"
	comm -12 "$scratch/export.paths" "$scratch/build.paths" >"$scratch/both"

	# Build-dir-only paths that are plausibly build outputs by location, unless they look
	# like source. Everything left is a real difference.
	: >"$scratch/only-build-real"
	while IFS= read -r path; do
		artifact=false
		for d in "${ARTIFACT_DIRS[@]}"; do
			[[ $path == "$d"* ]] && artifact=true && break
		done
		if $artifact && ! [[ $path =~ $SOURCE_RE ]]; then
			continue
		fi
		printf '%s\n' "$path" >>"$scratch/only-build-real"
	done <"$scratch/only-build"

	# Content comparison for the paths both sides have. `git hash-object` gives the same
	# object id git already stored for the export side, so this is an exact content
	# comparison with no second hashing scheme to get wrong. --no-filters because the
	# build dir may sit inside some other repo whose .gitattributes would otherwise
	# transform the bytes before hashing them.
	#
	# Symlinks are hashed by git as their TARGET STRING, while `git hash-object` on a
	# symlink path would follow it and hash the pointed-to file. There are only a handful
	# in a kernel tree, so they are split out and compared with readlink instead of
	# teaching the fast path about them.
	: >"$scratch/differ"
	: >"$scratch/regular.paths"
	: >"$scratch/link.paths"
	while IFS= read -r path; do
		if [[ -L $build_dir/$path ]]; then
			printf '%s\n' "$path" >>"$scratch/link.paths"
		else
			printf '%s\n' "$path" >>"$scratch/regular.paths"
		fi
	done <"$scratch/both"

	if [[ -s $scratch/regular.paths ]]; then
		(cd "$build_dir" && git hash-object --no-filters --stdin-paths \
			<"$scratch/regular.paths") >"$scratch/regular.sha"
		paste "$scratch/regular.paths" "$scratch/regular.sha" | sort >"$scratch/build.tsv"
		join -t$'\t' -j1 -o 0,1.3,2.2 "$scratch/export.tsv" "$scratch/build.tsv" |
			awk -F'\t' '$2 != $3 { print $1 }' >>"$scratch/differ"
	fi
	while IFS= read -r path; do
		want="$(git -C "$export_dir" show "$carried_tip:$path")"
		got="$(readlink "$build_dir/$path")"
		[[ $want == "$got" ]] || printf '%s\n' "$path" >>"$scratch/differ"
	done <"$scratch/link.paths"

	# The executable bit is content too, for these trees: half of scripts/ is shell and
	# perl that kbuild EXECUTES, so a file that lost +x somewhere between the patch series
	# and the export is a build that fails for a reason no content diff would explain.
	# git records it as mode 100755, so both sides can be reduced to a sorted path list
	# and compared as sets, restricted to the paths both trees have.
	awk -F'\t' '$2 == "100755" { print $1 }' "$scratch/export.tsv" |
		sort >"$scratch/export.exec"
	(cd "$build_dir" && find . -type f -perm -u+x -printf '%P\n') |
		sort >"$scratch/build.exec.all"
	comm -12 "$scratch/build.exec.all" "$scratch/both" >"$scratch/build.exec"
	comm -12 "$scratch/export.exec" "$scratch/both" >"$scratch/export.exec.both"
	{
		comm -23 "$scratch/export.exec.both" "$scratch/build.exec" |
			sed 's/$/\t(executable in the export, not in the build dir)/'
		comm -13 "$scratch/export.exec.both" "$scratch/build.exec" |
			sed 's/$/\t(executable in the build dir, not in the export)/'
	} >"$scratch/mode-differ"

	n_missing="$(wc -l <"$scratch/only-export")"
	n_extra="$(wc -l <"$scratch/only-build-real")"
	n_differ="$(wc -l <"$scratch/differ")"
	n_mode="$(wc -l <"$scratch/mode-differ")"
	n_compared="$(wc -l <"$scratch/both")"

	if ((n_missing == 0 && n_extra == 0 && n_differ == 0 && n_mode == 0)); then
		ok "$n_compared files compared, byte-identical — the exported carried tip IS the
       source Buildroot builds"
	else
		bad "the exported carried tip and $build_dir differ"
		note "$n_compared files compared"
		if ((n_missing)); then
			note "$n_missing in the export but NOT in the build dir:"
			sed 's/^/         /' "$scratch/only-export" | head -40 >&2
		fi
		if ((n_extra)); then
			note "$n_extra in the build dir but NOT in the export:"
			sed 's/^/         /' "$scratch/only-build-real" | head -40 >&2
			note 'If any of those are files kbuild GENERATES (a lexer, a table, a'
			note 'generated header), add its exact path to IGNORE_GLOBS in this script'
			note '-- do not widen the pattern to a whole directory.'
		fi
		if ((n_differ)); then
			note "$n_differ present in both but with different content:"
			sed 's/^/         /' "$scratch/differ" | head -40 >&2
		fi
		if ((n_mode)); then
			note "$n_mode differ in the executable bit:"
			sed 's/^/         /' "$scratch/mode-differ" | head -20 >&2
		fi
		note 'A difference here means the published tree is not the kernel the image'
		note 'ships. Fix the patch series or re-run the export; do not relax this check.'
	fi

	# --- 2b. The resolved configuration ------------------------------------------------
	if [[ ! -f $build_dir/.config ]]; then
		skip "config comparison — no .config in $build_dir (Buildroot has not
       configured the kernel there yet). Re-run after \`make linux-configure\`."
	else
		say 'Config: Buildroot .config vs `make ARCH=arm MiSTer_defconfig` on the export'
		# `make O=` rather than a copy of the export: same isolation, no 1.4GB copy, and
		# the export tree is provably untouched afterwards (asserted below).
		if make -C "$export_dir" O="$scratch/kconf" "${make_flags[@]}" \
			MiSTer_defconfig >"$scratch/kconf.log" 2>&1; then
			sort "$scratch/kconf/.config" | grep -E '^(CONFIG_|# CONFIG_)' >"$scratch/ours.cfg"
			sort "$build_dir/.config" | grep -E '^(CONFIG_|# CONFIG_)' >"$scratch/theirs.cfg"
			diff "$scratch/theirs.cfg" "$scratch/ours.cfg" >"$scratch/cfg.diff" || true

			# Symbols kconfig derives from whatever compiler is in front of it. A
			# difference in these says the two builds used different toolchains, which is
			# expected here and is not a configuration difference. Printed, never hidden.
			readonly TOOLCHAIN_RE='^[-+#]* *#? *CONFIG_(CC_VERSION_TEXT|CC_IS_|GCC_VERSION|CLANG_VERSION|LD_VERSION|LD_IS_|LLD_VERSION|AS_VERSION|AS_IS_|RUSTC_VERSION|RUSTC_LLVM_VERSION|PAHOLE_VERSION|CC_HAS_|CC_CAN_|AS_HAS_|LD_HAS_|LD_CAN_|RUSTC_HAS_|TOOLS_SUPPORT_|GCC_ASM_GOTO|CC_NO_|CC_IMPLICIT_FALLTHROUGH|PAHOLE_HAS_)'
			grep -E '^[<>]' "$scratch/cfg.diff" | sed 's/^[<>] //' | sort -u >"$scratch/cfg.lines" || true
			grep -E "$TOOLCHAIN_RE" "$scratch/cfg.lines" >"$scratch/cfg.toolchain" || true
			grep -Ev "$TOOLCHAIN_RE" "$scratch/cfg.lines" >"$scratch/cfg.real" || true

			n_tool="$(wc -l <"$scratch/cfg.toolchain")"
			n_real="$(wc -l <"$scratch/cfg.real")"
			if ((n_real == 0)); then
				ok "resolved configuration identical ($(wc -l <"$scratch/ours.cfg") symbols)"
			else
				bad "$n_real configuration symbols differ between Buildroot's .config and
       \`make ARCH=arm MiSTer_defconfig\` on the export:"
				sed 's/^/         /' "$scratch/cfg.real" | head -40 >&2
			fi
			if ((n_tool)); then
				note "$n_tool toolchain-derived symbols also differ; EXPECTED when the two"
				note 'builds used different compilers, and not a configuration difference:'
				sed 's/^/         /' "$scratch/cfg.toolchain" | head -12
			fi
		else
			bad "\`make ARCH=arm MiSTer_defconfig\` failed on the export; see $scratch/kconf.log"
			tail -20 "$scratch/kconf.log" >&2
		fi
	fi
fi

# --- 3. Buildability, with the maintainer's own DTB target ------------------------------

say 'Build'

if ! $do_build; then
	skip 'build — --no-build given'
else
	build_out="$scratch/build"
	if ! make -C "$export_dir" O="$build_out" "${make_flags[@]}" MiSTer_defconfig \
		>"$scratch/build.log" 2>&1; then
		bad 'make MiSTer_defconfig failed'
		tail -20 "$scratch/build.log" >&2
	else
		# THE DTBs ARE BUILT FIRST, AND SEPARATELY FROM zImage. They are the assertion
		# this section exists for -- the alias must compile to the same bytes as the file
		# it aliases -- and they take seconds, while zImage takes tens of minutes and
		# depends on host tools the DTBs do not need. Building them in one `make`
		# invocation made the whole check hostage to the slower, more fragile half: a
		# missing host `lz4` failed the zImage link and the DTBs, which had already been
		# produced, were never compared. Observed, not hypothetical.
		if ! make -C "$export_dir" O="$build_out" "${make_flags[@]}" \
			-j"$(nproc)" "$ALIAS_DTB" "$VANILLA_DTB" >>"$scratch/build.log" 2>&1; then
			bad "build failed for $ALIAS_DTB / $VANILLA_DTB — see $scratch/build.log"
			tail -30 "$scratch/build.log" >&2
		else
			alias_out="$build_out/arch/arm/boot/dts/$ALIAS_DTB"
			vanilla_out="$build_out/arch/arm/boot/dts/$VANILLA_DTB"
			ok "built $ALIAS_DTB (the name Linux-Kernel_MiSTer builds)"
			ok "built $VANILLA_DTB (the name Buildroot builds)"
			if cmp -s "$alias_out" "$vanilla_out"; then
				ok "both DTBs are byte-identical — the alias is an alias
       sha256 $(sha256sum "$alias_out" | cut -d' ' -f1)
       $(wc -c <"$alias_out") bytes"
			else
				bad "the two DTB names produce DIFFERENT bytes:
       $ALIAS_DTB   $(sha256sum "$alias_out" | cut -d' ' -f1)
       $VANILLA_DTB $(sha256sum "$vanilla_out" | cut -d' ' -f1)
       The generated alias has become a second board description."
			fi

			# Buildroot's own DTB, when it has built one. Not fatal on its own — a
			# different dtc can legitimately lay a blob out differently — so this is
			# reported either way rather than asserted.
			br_dtb="$build_dir/arch/arm/boot/dts/$VANILLA_DTB"
			if [[ -n $build_dir && -f $br_dtb ]]; then
				if cmp -s "$vanilla_out" "$br_dtb"; then
					ok "DTB matches the one in $build_dir"
				else
					note "DTB differs from $build_dir's:"
					note "  export     $(sha256sum "$vanilla_out" | cut -d' ' -f1)"
					note "  build dir  $(sha256sum "$br_dtb" | cut -d' ' -f1)"
					note '  (different dtc versions can differ legitimately; compare `fdtdump` output)'
				fi
			elif [[ -n $build_dir ]]; then
				skip "DTB comparison against $build_dir — it has no built DTB"
			fi
		fi

		# zImage needs a HOST compressor that kbuild shells out to, named by the config.
		# Missing it is an environment gap, not a defect in the exported tree, and the
		# make failure it produces ("/bin/sh: 1: lz4: not found", after a complete and
		# successful vmlinux link) reads like a broken kernel. So it is detected up front
		# and reported as a SKIP naming the package to install -- a skip is explicitly not
		# a pass in this script's summary.
		compressor=''
		compressor_sym=''
		for pair in KERNEL_GZIP:gzip KERNEL_LZ4:lz4 KERNEL_LZO:lzop KERNEL_LZMA:lzma \
			KERNEL_XZ:xz KERNEL_ZSTD:zstd KERNEL_BZIP2:bzip2; do
			grep -q "^CONFIG_${pair%%:*}=y" "$build_out/.config" || continue
			compressor_sym="CONFIG_${pair%%:*}"
			compressor="${pair##*:}"
			break
		done
		if [[ -n $compressor ]] && ! command -v "$compressor" >/dev/null 2>&1; then
			skip "zImage — this configuration sets $compressor_sym and the host has
       no \`$compressor\`, which kbuild shells out to for arch/arm/boot/compressed.
       The kernel itself compiles; only the final compression step cannot run.
       Install $compressor and re-run to close this gap."
		elif ! make -C "$export_dir" O="$build_out" "${make_flags[@]}" LOCALVERSION= \
			-j"$(nproc)" zImage >>"$scratch/build.log" 2>&1; then
			bad "build failed for zImage — see $scratch/build.log"
			tail -30 "$scratch/build.log" >&2
		else
			ok "built zImage ($(wc -c <"$build_out/arch/arm/boot/zImage") bytes)"
		fi
	fi

	# `make O=` must not have written into the export. Asserted, not assumed: a kbuild
	# change that started writing into the source tree would otherwise turn this
	# read-only check into one that dirties the thing it is checking.
	if [[ -z "$(git -C "$export_dir" status --porcelain)" ]]; then
		ok 'the export tree is unmodified by this check'
	else
		bad "this check left $export_dir dirty:"
		git -C "$export_dir" status --porcelain | sed 's/^/         /' >&2
	fi
fi

# --- 4. Summary --------------------------------------------------------------------------

printf '\n'
if ((fails)); then
	printf 'RESULT: FAIL — %d check(s) failed, %d passed, %d skipped.\n' \
		"$fails" "$passes" "$skips" >&2
	exit 1
fi
printf 'RESULT: PASS — %d checks passed, %d skipped.\n' "$passes" "$skips"
printf '  export     %s\n' "$export_dir"
printf '  tag        %s\n' "$tag"
[[ -n $build_dir ]] && printf '  build dir  %s\n' "$build_dir"
((skips == 0)) ||
	printf '  NOTE: %d check(s) were SKIPPED, not passed — see the "skip" lines above.\n' "$skips"
exit 0
