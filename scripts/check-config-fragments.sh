#!/usr/bin/env bash
#
# check-config-fragments.sh — regenerate every Buildroot configuration from
# its fragment stack and prove the stack means what it says
# (docs/buildroot-config.md §1, §11).
#
# The monolithic defconfigs were split into configs/fragments/ (stacks.mk
# lists which fragments make which configuration). merge_config.sh +
# olddefconfig is a forgiving pipeline: a fragment can redefine a symbol an
# earlier one set (merge_config.sh only WARNS), and olddefconfig silently
# drops any symbol whose dependencies are unmet or whose name no longer
# exists in this Buildroot. Neither is an error at build time, both ship a
# different image than the fragments describe. This script turns each into a
# CI failure, and pins the resolved DE10 configuration with a golden hash so
# any drift — a Buildroot bump changing a default underneath us, a fragment
# edit with an unexpected knock-on — fails until the hash is deliberately
# updated with a commit that explains why.
#
# What it asserts, per stack (de10nano, de10nano-kernel, de25nano, and
# de10nano-kernel + configs/mister_<variant>.fragment for every kernel
# variant):
#   (a) NO REDEFINITION between fragments: a symbol defined by two fragments
#       of one stack (same value or not) is a layering smell — a symbol set
#       in common and overridden per board should have been board-only.
#       Checked from the fragment text (independent of merge_config.sh's
#       output format) AND merge_config.sh's own "redefined" warnings are
#       captured and must be empty. The ONE designed exception is a kernel
#       variant's fragment overriding the kernel version + patch dir
#       (mister_rt.fragment) — ALLOWED_OVERRIDES below, per variant.
#   (b) EVERY FRAGMENT SYMBOL SURVIVES olddefconfig: each `BR2_X=val` line
#       must appear verbatim in the resolved .config, and each
#       `# BR2_X is not set` must resolve to exactly that line (a typo'd
#       symbol name is absent from the resolved config in EITHER form, and
#       kconfig says nothing). This is what catches a dropped symbol (unmet
#       dependency, renamed option after a Buildroot bump, typo) that kconfig
#       would otherwise discard silently — the DE25 bring-up's
#       fragment-vs-resolved comparison, made permanent.
#   (c) RESOLVED-LEVEL LOCKSTEP: the de10nano and de10nano-kernel resolved
#       configs agree on every symbol except a named list of designed
#       divergences (packages, init/shell choice, rootfs image types, system
#       configuration, package-driven glibc gconv copy). The text-level half
#       of this guarantee (scripts/check-kernel-defconfig-sync.sh) runs
#       without a Buildroot tree; this half is what proves the shared
#       fragments still resolve identically once package selects are in play.
#   (d) GOLDEN HASH: sha256 of the NORMALISED resolved .config equals the
#       value recorded in configs/fragments/golden.sha256 for the pinned
#       Buildroot version. Normalisation keeps only the SET symbols
#       (`BR2_X=...`), and drops what legitimately varies by host or checkout
#       (see normalise_config) plus the two kernel-version symbols Renovate
#       moves weekly (BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE and kconfig's
#       derived BR2_LINUX_KERNEL_VERSION — their landing is already proved by
#       (b)), so the hash is stable across machines and across routine
#       kernel bumps of every pin (6.18.y, the rt 7.2.y pin, the DE25 pin)
#       and moves ONLY when the resolved configuration really changes.
#       olddefconfig is also run with the HOST inputs pinned to canonical
#       values (HOSTARCH, HOSTCC_VERSION — Buildroot derives BR2_HOSTARCH,
#       BR2_HOST_GCC_AT_LEAST_* and every host-gated package from them), so
#       the resolved config the check reasons about is a pure function of
#       (fragments, Buildroot version), never of the machine running it.
#       Two outcomes: a MISMATCH against a recorded line is a failure (the
#       configuration drifted; if intended, --update-golden and commit with
#       the reason). NO line at all for the pinned Buildroot version is a
#       ::warning, not a failure — a Buildroot bump changes defaults and is
#       expected to move every hash; the check prints the new lines ready to
#       paste, .github/workflows/renovate-hash-sync.yml case 8 commits them
#       on a Renovate bump PR, and the build is allowed to proceed so the
#       bump PR still proves it builds.
#
# Cost: needs the pinned Buildroot tree (fetched/unpacked by `make
# buildroot-unpack` if absent — a 10 MB download, no compile beyond
# Buildroot's own kconfig `conf` binary) and runs olddefconfig once per stack.
# Seconds locally; a minute or two on a cold CI runner. No toolchain, no
# packages, no image.
#
# Usage: scripts/check-config-fragments.sh [--update-golden] [--keep] [STACK...]
#   STACK      limit to the named stack(s) (de10nano, de10nano-kernel,
#              de25nano, or a kernel variant name such as rt); default: all.
#   --update-golden  rewrite configs/fragments/golden.sha256 from the current
#              resolved configs instead of asserting against it.
#   --keep     leave output-config-check/ in place for inspection (it is
#              always left in place on failure).
#   CHECK_CONFIG_BR_DIR=<path>  use an already-unpacked Buildroot tree
#              instead of the wrapper's work/buildroot (tests, CI fixtures).
#   CHECK_CONFIG_HOSTARCH / CHECK_CONFIG_HOSTCC_VERSION  override the pinned
#              host inputs (self-tests only: the golden must NOT move).
#
# It also guards the hard-coded fragment PATHS outside stacks.mk (§ "path
# consumers" below): a fragment rename with stacks.mk updated would otherwise
# pass every check while action.yml's hashFiles() lists, renovate.json's
# managerFilePatterns and the scripts that read a pin by filename all went
# silently stale.
#
# Exit: 0 = every stack passes; 1 = an assertion failed; 2 = usage/IO error.

set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/board-expectations.sh
. "$ROOT/scripts/lib/board-expectations.sh"
# shellcheck source=scripts/lib/config-stacks.sh
. "$ROOT/scripts/lib/config-stacks.sh"

GOLDEN="$ROOT/configs/fragments/golden.sha256"
CHECK_DIR="$ROOT/output-config-check"

# Canonical host inputs for olddefconfig (see (d) above). Buildroot computes
# both with `:=` from the real host compiler; a command-line assignment
# overrides that. x86_64 + GCC 14 is what the CI runners and the developer
# hosts have had since the 2026.05 bump; the values only have to be FIXED,
# not true, for the resolved config to be host-independent.
PIN_HOSTARCH="${CHECK_CONFIG_HOSTARCH:-x86_64}"
PIN_HOSTCC_VERSION="${CHECK_CONFIG_HOSTCC_VERSION:-14}"

# Per-variant allowlist for (a): symbols a kernel variant's fragment is
# EXPECTED to redefine on top of the kernel-only stack. Anything else a
# variant redefines is a failure, so a variant that starts overriding, say,
# the toolchain has to come here and say so.
declare -A ALLOWED_OVERRIDES=(
	[rt]="BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE BR2_LINUX_KERNEL_PATCH"
)

# Designed divergences for (c): symbol-name PREFIXES on which the resolved
# de10nano and de10nano-kernel configs may differ. Everything else must be
# identical. Keep this list short and specific — it is the definition of
# "what a kernel variant is allowed not to share with the image".
LOCKSTEP_DIVERGENCE_PREFIXES="
BR2_PACKAGE_
BR2_INIT_
BR2_SYSTEM_
BR2_ROOTFS_OVERLAY
BR2_ROOTFS_POST_BUILD_SCRIPT
BR2_ROOTFS_DEVICE_CREATION_
BR2_TARGET_ROOTFS_
BR2_TARGET_GENERIC_
BR2_TARGET_TZ_
BR2_TARGET_LOCALTIME
BR2_GENERATE_LOCALE
BR2_TOOLCHAIN_GLIBC_GCONV_LIBS_
BR2_GDB_VERSION
BR2_DEFCONFIG
"

UPDATE_GOLDEN=false
KEEP=false
only=()
while [ "$#" -gt 0 ]; do
	case "$1" in
		--update-golden) UPDATE_GOLDEN=true ;;
		--keep) KEEP=true ;;
		-h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "check-config-fragments: unknown option '$1'" >&2; exit 2 ;;
		*) only+=("$1") ;;
	esac
	shift
done

die() { echo "check-config-fragments: FATAL: $*" >&2; exit 2; }
fail() { echo "FAIL: $*" >&2; rc=1; }
rc=0

[ -f "$CONFIG_STACKS_MK" ] || die "missing $CONFIG_STACKS_MK"

# --- Buildroot tree -----------------------------------------------------------
# The wrapper Makefile owns fetching/verifying/unpacking the pinned tarball;
# reuse it rather than re-implementing the hash check here. `buildroot-unpack`
# has no hostshim prerequisite and olddefconfig needs none (Buildroot's
# dependencies.sh only runs for build targets).
BR_DIR="${CHECK_CONFIG_BR_DIR:-$ROOT/work/buildroot}"
if [ -z "${CHECK_CONFIG_BR_DIR:-}" ]; then
	make -C "$ROOT" --no-print-directory buildroot-unpack >/dev/null || die "make buildroot-unpack failed"
fi
[ -x "$BR_DIR/support/kconfig/merge_config.sh" ] || die "no merge_config.sh under $BR_DIR"
BR_VERSION=$(sed -n -e 's/[[:space:]]*$//' -e 's/^BUILDROOT_VERSION[[:space:]]*?=[[:space:]]*//p' "$ROOT/Makefile" | head -1)
[ -n "$BR_VERSION" ] || die "could not read BUILDROOT_VERSION from Makefile"

# --- Stack registry -----------------------------------------------------------
# stacks.mk's stacks, plus one synthetic stack per kernel variant fragment
# (configs/mister_<name>.fragment layered on the kernel-only stack — the same
# registry .github/actions/buildroot-build and scripts/list-kernel-variants.sh
# use). Order: stacks.mk order, then variants sorted by name.
declare -A STACK_FILES=()
stack_order=()
while IFS= read -r var; do
	[ -n "$var" ] || continue
	label=$(config_stack_label "$var")
	STACK_FILES[$label]=$(config_stack_files "$var" | tr '\n' ' ')
	stack_order+=("$label")
done < <(config_stack_vars)
[ -n "${STACK_FILES[de10nano-kernel]+set}" ] || die "stacks.mk defines no DE10NANO_KERNEL stack — kernel variants have no base"
shopt -s nullglob
for f in "$ROOT"/configs/mister_*.fragment; do
	name="${f#"$ROOT"/configs/mister_}"; name="${name%.fragment}"
	STACK_FILES[$name]="${STACK_FILES[de10nano-kernel]}$f "
	stack_order+=("$name")
done
shopt -u nullglob

if [ "${#only[@]}" -gt 0 ]; then
	for s in "${only[@]}"; do
		[ -n "${STACK_FILES[$s]+set}" ] || die "unknown stack '$s' (known: ${stack_order[*]})"
	done
	stack_order=("${only[@]}")
fi

# --- Normalisation for the golden hash ----------------------------------------
# Keep: every SET symbol (`BR2_X=...`). `# BR2_X is not set` lines are
# dropped from the hash — losslessly for drift detection, since a symbol that
# flips on shows up as a new set line and one that flips off as a vanished
# set line, and the not-set list is exactly where host-gated symbols (a
# package `depends on BR2_HOSTARCH = ...`, a host-gcc floor) appear or
# disappear between machines. Then drop the set symbols that legitimately
# vary by host or checkout even with the host inputs pinned:
#   BR2_HOSTARCH, BR2_HOST_GCC_VERSION, BR2_HOST_GCC_AT_LEAST_*   the build host
#   BR2_PACKAGE_*_ARCH_SUPPORTS, BR2_PACKAGE_HOST_GO_BIN_HOST_ARCH,
#   BR2_PACKAGE_PROVIDES_HOST_RUSTC                                HOSTARCH-derived
#   BR2_PACKAGE_(HOST_)GOBJECT_INTROSPECTION, BR2_PACKAGE_HOST_QEMU*,
#   BR2_PACKAGE_LIBGLIB2_BOOTSTRAP, BR2_PACKAGE_PYTHON_GOBJECT   `depends on
#       BR2_HOST_GCC_AT_LEAST_*` consumers that are =y here (measured: these
#       are the only set lines that move between HOSTCC_VERSION 5/9/14 —
#       the fragment lines among them are still proved by (b))
#   BR2_VERSION, BR2_EXTERNAL_MISTER_*                             git-describe / absolute path
#   BR2_DEFCONFIG                                                  savedefconfig's output path
#   BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE, BR2_LINUX_KERNEL_VERSION  the Renovate-
#       managed kernel pin and kconfig's copy of it (landing proved by (b))
# Everything else is the configuration.
normalise_config() {
	grep -E '^BR2_[A-Za-z0-9_]+=' "$1" \
		| grep -vE '^(BR2_HOSTARCH|BR2_HOST_GCC_VERSION|BR2_HOST_GCC_AT_LEAST_|BR2_VERSION=|BR2_EXTERNAL_MISTER_|BR2_DEFCONFIG=|BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE=|BR2_LINUX_KERNEL_VERSION=)' \
		| grep -vE '^(BR2_PACKAGE_[A-Z0-9_]+_ARCH_SUPPORTS=|BR2_PACKAGE_HOST_GO_BIN_HOST_ARCH=|BR2_PACKAGE_PROVIDES_HOST_RUSTC=)' \
		| grep -vE '^(BR2_PACKAGE_GOBJECT_INTROSPECTION=|BR2_PACKAGE_HOST_GOBJECT_INTROSPECTION=|BR2_PACKAGE_HOST_QEMU|BR2_PACKAGE_LIBGLIB2_BOOTSTRAP=|BR2_PACKAGE_PYTHON_GOBJECT=)'
}

golden_has_version() { # any line recorded for BR_VERSION at all?
	[ -f "$GOLDEN" ] && awk -v v="$BR_VERSION" '$1 == v { found = 1 } END { exit !found }' "$GOLDEN"
}

golden_lookup() { # $1 = stack -> recorded hash for BR_VERSION, or empty
	[ -f "$GOLDEN" ] || return 0
	awk -v v="$BR_VERSION" -v s="$1" '$1 == v && $2 == s { print $3 }' "$GOLDEN" | head -1
}

# --- Per-stack work -----------------------------------------------------------
declare -A NEW_GOLDEN=()
declare -A RESOLVED=()
missing_golden=0
for stack in "${stack_order[@]}"; do
	# shellcheck disable=SC2206 # the file list is space-separated on purpose
	files=(${STACK_FILES[$stack]})
	echo "==> $stack: ${files[*]#"$ROOT"/}"
	for f in "${files[@]}"; do
		[ -f "$f" ] || die "$stack: missing fragment $f"
	done
	odir="$CHECK_DIR/$stack"
	rm -rf "$odir"; mkdir -p "$odir"

	# (a) text-level redefinition check, fragment by fragment in merge order.
	declare -A seen=()
	# shellcheck disable=SC2086 # word splitting of the allowlist is intended
	allowed=" ${ALLOWED_OVERRIDES[$stack]:-} "
	for f in "${files[@]}"; do
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			sym=$(config_line_symbol "$line")
			if [ -n "${seen[$sym]+set}" ]; then
				case "$allowed" in
					*" $sym "*) ;;
					*) fail "$stack: ${f#"$ROOT"/} redefines $sym, already defined by ${seen[$sym]#"$ROOT"/}. A symbol belongs in exactly one fragment of a stack (docs/buildroot-config.md §1); a kernel variant may override only what ALLOWED_OVERRIDES in $(basename "$0") lists." ;;
				esac
			fi
			seen[$sym]="$f"
		done < <(config_strip_fragment "$f")
	done
	unset seen

	# Merge (Buildroot's own tool, the same call the Makefile makes), keeping
	# its stdout so its own redefinition warnings can be asserted empty too.
	# TMPDIR: merge_config.sh mktemp's under it; keep that inside our dir.
	if ! (cd "$BR_DIR" && TMPDIR="$odir" KCONFIG_CONFIG="$odir/.config" \
			./support/kconfig/merge_config.sh -m -O "$odir" "${files[@]}") >"$odir/merge.log" 2>&1; then
		cat "$odir/merge.log" >&2
		die "$stack: merge_config.sh failed"
	fi
	if grep -q 'is redefined by fragment' "$odir/merge.log"; then
		while IFS= read -r sym; do
			case "$allowed" in
				*" $sym "*) ;;
				*) fail "$stack: merge_config.sh reports $sym redefined (see $odir/merge.log)" ;;
			esac
		done < <(sed -n 's/^Value of \([A-Za-z0-9_]*\) is redefined by fragment .*/\1/p' "$odir/merge.log")
	fi

	if ! make -C "$BR_DIR" O="$odir" BR2_EXTERNAL="$ROOT" BR2_DL_DIR="$ROOT/dl" \
			HOSTARCH="$PIN_HOSTARCH" HOSTCC_VERSION="$PIN_HOSTCC_VERSION" \
			olddefconfig >"$odir/olddefconfig.log" 2>&1; then
		cat "$odir/olddefconfig.log" >&2
		die "$stack: olddefconfig failed"
	fi
	resolved="$odir/.config"
	RESOLVED[$stack]="$resolved"

	# (b) every effective fragment line survives. "Effective" = the LAST
	# definition in merge order, so an allowed variant override is checked
	# against the override's value, not the base's.
	declare -A effective=()
	for f in "${files[@]}"; do
		while IFS= read -r line; do
			[ -n "$line" ] || continue
			effective[$(config_line_symbol "$line")]="$line"
		done < <(config_strip_fragment "$f")
	done
	dropped=0
	for sym in "${!effective[@]}"; do
		line="${effective[$sym]}"
		case "$line" in
			"# "*" is not set")
				# The symbol must come back as EXACTLY this line. `=y`/`=m`
				# means the not-set was overridden by a select or default;
				# absent in both forms means kconfig never heard of the name
				# (typo, or the option no longer exists in this Buildroot).
				if ! grep -qxF -- "$line" "$resolved"; then
					actual=$(grep -E "^(# )?$sym( is not set|=)" "$resolved" || echo "<absent in both forms — misspelt or unknown symbol in Buildroot $BR_VERSION>")
					fail "$stack: fragment says '$line' but the resolved .config has $actual"
					dropped=$((dropped + 1))
				fi
				;;
			*)
				if ! grep -qxF -- "$line" "$resolved"; then
					actual=$(grep -E "^(# )?$sym( is not set|=)" "$resolved" || echo "<absent — unmet dependency or unknown symbol in Buildroot $BR_VERSION>")
					fail "$stack: '$line' did not survive olddefconfig; resolved: $actual"
					dropped=$((dropped + 1))
				fi
				;;
		esac
	done
	echo "    ${#effective[@]} fragment symbol(s) checked against the resolved .config, $dropped dropped"
	unset effective

	# (d) golden hash of the normalised resolved config.
	normalise_config "$resolved" >"$odir/normalised.config"
	hash=$(sha256sum "$odir/normalised.config" | cut -d' ' -f1)
	NEW_GOLDEN[$stack]="$hash"
	if [ "$UPDATE_GOLDEN" = false ]; then
		want=$(golden_lookup "$stack")
		if [ -z "$want" ] && ! golden_has_version; then
			# A Buildroot bump: nothing recorded for this version yet. Warn,
			# print the line, let the build proceed (see (d) in the header).
			echo "::warning::$stack: no golden hash recorded for Buildroot $BR_VERSION in ${GOLDEN#"$ROOT"/} -- a Buildroot bump. Expected line: '$BR_VERSION $stack $hash'. renovate-hash-sync.yml case 8 commits it on a Renovate PR; by hand: '$(basename "$0") --update-golden', then commit with what changed."
			missing_golden=$((missing_golden + 1))
		elif [ -z "$want" ]; then
			fail "$stack: ${GOLDEN#"$ROOT"/} records Buildroot $BR_VERSION for other stacks but has no line for '$stack' (a new stack, or a deleted line). Run '$(basename "$0") --update-golden' and commit the new line with the reason."
		elif [ "$want" != "$hash" ]; then
			fail "$stack: resolved configuration DRIFTED — sha256 of the normalised .config is $hash, golden says $want (${GOLDEN#"$ROOT"/}). If the change is intended, run '$(basename "$0") --update-golden' and commit the new hash with a message saying what changed and why; the normalised config is at ${odir#"$ROOT"/}/normalised.config for diffing against the previous good run."
		else
			echo "    golden hash matches ($hash)"
		fi
	fi
done

# (c) resolved-level lockstep between the image and the kernel-only base.
if [ -n "${RESOLVED[de10nano]+set}" ] && [ -n "${RESOLVED[de10nano-kernel]+set}" ]; then
	div=$(diff \
		<(normalise_config "${RESOLVED[de10nano]}" | sort) \
		<(normalise_config "${RESOLVED[de10nano-kernel]}" | sort) \
		| sed -n 's/^[<>] //p' | sed -e 's/^# \(BR2_[A-Za-z0-9_]*\) is not set$/\1/' -e 's/=.*$//' | sort -u || true)
	bad=""
	while IFS= read -r sym; do
		[ -n "$sym" ] || continue
		ok=false
		while IFS= read -r pfx; do
			[ -n "$pfx" ] || continue
			case "$sym" in "$pfx"*) ok=true; break ;; esac
		done <<< "$LOCKSTEP_DIVERGENCE_PREFIXES"
		[ "$ok" = true ] || bad="$bad $sym"
	done <<< "$div"
	if [ -n "$bad" ]; then
		fail "resolved-level lockstep: de10nano and de10nano-kernel differ on:$bad — outside the designed divergences (LOCKSTEP_DIVERGENCE_PREFIXES in $(basename "$0")). A variant kernel would be built with different toolchain/kernel settings than the image (docs/buildroot-config.md §4)."
	else
		echo "==> resolved-level lockstep: de10nano and de10nano-kernel agree on every symbol outside the designed divergences ($(printf '%s\n' "$div" | grep -c . ) differing symbols, all allowed)"
	fi
elif [ "${#only[@]}" -eq 0 ]; then
	fail "resolved-level lockstep: de10nano or de10nano-kernel stack missing from stacks.mk"
fi

# --- Path consumers outside stacks.mk -----------------------------------------
# stacks.mk is the source of truth for WHICH fragments exist, but several
# consumers must name fragment files literally and cannot read it:
# GitHub's hashFiles() (action.yml's two dl-cache keys), Renovate's
# managerFilePatterns, the workflow path filter, and the scripts that read a
# pin off one fragment by filename. A rename that updates stacks.mk passes
# (a)-(d) while all of those go stale. Two asserts:
#   1. every `configs/fragments/<name>` token in the code/CI surface
#      (Makefile, scripts/, .github/, renovate.json -- not docs, which may
#      legitimately name history) must exist in the tree;
#   2. action.yml's hashFiles() list containing de10nano-image must equal the
#      DE10NANO stack's files, and the one containing kernel-only must equal
#      the DE10NANO_KERNEL stack's (the format('mister_{0}.fragment') item is
#      the variant's own fragment and is skipped).
if [ "${#only[@]}" -eq 0 ]; then
	action="$ROOT/.github/actions/buildroot-build/action.yml"
	while IFS= read -r tok; do
		[ -n "$tok" ] || continue
		if [ ! -e "$ROOT/$tok" ]; then
			fail "path consumer: '$tok' is named in the code/CI surface but does not exist -- a fragment was renamed or moved without updating every consumer ($(grep -rlF -- "$tok" "$ROOT/Makefile" "$ROOT/scripts" "$ROOT/.github" "$ROOT/renovate.json" | sed "s|^$ROOT/||" | tr '\n' ' '))"
		fi
	done < <(grep -rhoE 'configs/fragments/[A-Za-z0-9_.\\-]+' "$ROOT/Makefile" "$ROOT/scripts" "$ROOT/.github" "$ROOT/renovate.json" \
		| sed -e 's/\\*\././g' -e 's/[.,:;)]*$//' | sort -u)
	if [ -f "$action" ]; then
		check_hashfiles() { # $1 = stack var, $2 = distinguishing fragment name
			local want got
			want=$(config_stack_files "$1" | sed "s|^$ROOT/||" | sort | tr '\n' ' ')
			got=$(grep -oE "hashFiles\([^)]*configs/fragments/$2\.fragment[^)]*\)" "$action" \
				| grep -oE "'configs/fragments/[^']+'" | tr -d "'" | sort -u | tr '\n' ' ')
			if [ -z "$got" ]; then
				fail "path consumer: $action has no hashFiles() list naming configs/fragments/$2.fragment -- the dl-cache key for the $(config_stack_label "$1") stack is gone"
			elif [ "$got" != "$want" ]; then
				fail "path consumer: $action's hashFiles() list for the $(config_stack_label "$1") stack is [$got] but stacks.mk says [$want] -- keep the two in step (hashFiles cannot read stacks.mk)"
			fi
		}
		check_hashfiles DE10NANO de10nano-image
		check_hashfiles DE10NANO_KERNEL kernel-only
	else
		fail "path consumer: $action not found"
	fi
fi

# --- Golden file --------------------------------------------------------------
if [ "$UPDATE_GOLDEN" = true ]; then
	{
		echo "# configs/fragments/golden.sha256 — sha256 of each stack's NORMALISED resolved"
		echo "# .config for the pinned Buildroot version (scripts/check-config-fragments.sh"
		echo "# (d); docs/buildroot-config.md §11). Regenerate ONLY with"
		echo "#   scripts/check-config-fragments.sh --update-golden"
		echo "# and say in the commit message what changed and why. Columns:"
		echo "# <BUILDROOT_VERSION> <stack> <sha256>"
		for stack in "${stack_order[@]}"; do
			printf '%s %s %s\n' "$BR_VERSION" "$stack" "${NEW_GOLDEN[$stack]}"
		done
		# Keep other stacks' lines for this version and every other version's
		# lines untouched, so a partial run cannot delete what it did not check.
		if [ -f "$GOLDEN" ]; then
			awk -v v="$BR_VERSION" -v keep=" ${stack_order[*]} " '
				/^#/ { next }
				NF == 3 && !($1 == v && index(keep, " " $2 " ")) { print }
			' "$GOLDEN"
		fi
	} | awk '/^#/ || !seen[$0]++' >"$GOLDEN.tmp"
	mv "$GOLDEN.tmp" "$GOLDEN"
	echo "==> wrote ${GOLDEN#"$ROOT"/}"
fi

if [ "$rc" -eq 0 ]; then
	[ "$KEEP" = true ] || rm -rf "$CHECK_DIR"
	if [ "$missing_golden" -gt 0 ]; then
		echo "check-config-fragments: OK with $missing_golden WARNING(s) — ${#stack_order[@]} stack(s) regenerate cleanly from their fragments, but ${GOLDEN#"$ROOT"/} has no lines for Buildroot $BR_VERSION yet (see the warnings above)"
	else
		echo "check-config-fragments: OK — ${#stack_order[@]} stack(s) regenerate cleanly from their fragments (Buildroot $BR_VERSION)"
	fi
else
	echo "check-config-fragments: FAILED — resolved configs left under ${CHECK_DIR#"$ROOT"/}/ for inspection" >&2
fi
exit "$rc"
