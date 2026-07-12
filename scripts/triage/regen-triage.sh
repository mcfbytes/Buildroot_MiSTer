#!/bin/sh
# regen-triage.sh -- regenerate every number in docs/patch-provenance.md §1 from scratch.
#
# P0.4. Establishes the trustworthy baseline for the kernel patch triage:
#   1. fetch + hash-verify a pristine linux-5.15.1 from kernel.org
#   2. prove the fork's "v5.15.1" version-bump commit lands a PRISTINE upstream tree
#      (=> the commits after it are the complete MiSTer delta)
#   3. compute the authoritative HEAD-vs-pristine content delta
#   4. reconcile that content delta against the commit list, both directions
#
# Text output only. Writes nothing outside work/ (gitignored) and a temp dir.
# Standing rule 1: no binaries in git, ever.
#
# Usage:  scripts/triage/regen-triage.sh [WORKDIR]     (default: ./work)

set -eu

WORK="${1:-work}"
KVER=5.15.1
KURL="https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KVER}.tar.xz"
SUMS_URL="https://cdn.kernel.org/pub/linux/kernel/v5.x/sha256sums.asc"
FORK="$WORK/Linux-Kernel_MiSTer"
PRISTINE="$WORK/linux-${KVER}"

# The fork's last whole-tree "version bump" commit, message "v5.15.1".
# NOTE: the fork has ZERO git tags -- `git log v5.15.1..HEAD` cannot work. Use the SHA.
BASE=aba1ef4c1101429fd2addb2be560c6370200ed0f

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# --------------------------------------------------------------------------
say "0. Preconditions"
[ -d "$FORK/.git" ] || { echo "FATAL: $FORK not found. See docs/reference-materials.md."; exit 1; }
printf 'fork HEAD : %s\n' "$(git -C "$FORK" log -1 --format='%H %s')"
printf 'fork tags : %s (expect: 0 -- it is not a git-ancestry fork of torvalds/linux)\n' \
       "$(git -C "$FORK" tag -l | wc -l)"

# --------------------------------------------------------------------------
say "1. Pristine linux-${KVER} from kernel.org (hash-verified)"
mkdir -p "$WORK"
if [ ! -d "$PRISTINE" ]; then
    [ -f "$WORK/linux-${KVER}.tar.xz" ] || curl -fsSL -o "$WORK/linux-${KVER}.tar.xz" "$KURL"
    curl -fsSL -o "$WORK/sha256sums-${KVER}.asc" "$SUMS_URL"

    want=$(grep -E "linux-${KVER}\.tar\.xz\$" "$WORK/sha256sums-${KVER}.asc" | awk '{print $1}')
    got=$(sha256sum "$WORK/linux-${KVER}.tar.xz" | awk '{print $1}')
    printf 'kernel.org sha256 : %s\ndownloaded sha256 : %s\n' "$want" "$got"
    [ -n "$want" ] && [ "$want" = "$got" ] || { echo "FATAL: SHA-256 mismatch"; exit 1; }
    echo "SHA-256 OK"

    tar xf "$WORK/linux-${KVER}.tar.xz" -C "$WORK"
fi

# path -> "mode blob" listings. Git blob SHA equality == exact content equality.
if [ ! -d "$PRISTINE/.git" ]; then
    ( cd "$PRISTINE" && git init -q . && git add -Af . )   # -f: ignore the kernel's own .gitignore
fi
git -C "$PRISTINE" ls-files -s | awk '{print $4" "$1" "$2}' | sort > "$TMP/P"
git -C "$FORK" ls-tree -r "$BASE" | awk '{print $4" "$1" "$3}' | sort > "$TMP/A"
git -C "$FORK" ls-tree -r HEAD    | awk '{print $4" "$1" "$3}' | sort > "$TMP/H"

printf 'pristine v%s : %6d files\n' "$KVER" "$(wc -l < "$TMP/P")"
printf 'fork @ %.9s : %6d files\n'  "$BASE"  "$(wc -l < "$TMP/A")"
printf 'fork @ HEAD   : %6d files\n'         "$(wc -l < "$TMP/H")"

# --------------------------------------------------------------------------
say "2. THE LOAD-BEARING QUESTION: is the fork's v5.15.1 tree pristine?"
cut -d' ' -f1 "$TMP/P" > "$TMP/Pp"; cut -d' ' -f1 "$TMP/A" > "$TMP/Ap"
join "$TMP/P" "$TMP/A" -o 0,1.3,2.3,1.2,2.2 | awk '$2!=$3 || $4!=$5 {print $1}' > "$TMP/base-modified"
comm -13 "$TMP/Pp" "$TMP/Ap" > "$TMP/base-added"
comm -23 "$TMP/Pp" "$TMP/Ap" > "$TMP/base-missing"

printf 'files with DIFFERENT CONTENT/MODE : %s   (expect 0)\n' "$(wc -l < "$TMP/base-modified")"
printf 'files ADDED by MiSTer at the bump  : %s   (expect 0)\n' "$(wc -l < "$TMP/base-added")"
printf 'files MISSING from the fork        : %s   (expect 11 -- import artefacts)\n' \
       "$(wc -l < "$TMP/base-missing")"
if [ ! -s "$TMP/base-modified" ] && [ ! -s "$TMP/base-added" ]; then
    echo
    echo "RESULT: the version-bump commit lands a PRISTINE upstream tree."
    echo "        => the commits after ${BASE%??????????????????????????????} ARE the complete MiSTer delta."
else
    echo "RESULT: *** the bump commit already carries MiSTer changes -- the commit list is NOT sufficient ***"
fi
echo "--- the missing files (none is compiled into a kernel; none is touched by any commit):"
sed 's/^/    /' "$TMP/base-missing"

# --------------------------------------------------------------------------
say "3. Authoritative delta: fork HEAD vs pristine v${KVER}"
cut -d' ' -f1 "$TMP/H" > "$TMP/Hp"
comm -13 "$TMP/Pp" "$TMP/Hp" > "$TMP/added"
comm -23 "$TMP/Pp" "$TMP/Hp" > "$TMP/removed"
join "$TMP/P" "$TMP/H" -o 0,1.3,2.3,1.2,2.2 | awk '$2!=$3 || $4!=$5 {print $1}' > "$TMP/modified"

printf 'ADDED    : %5d\n' "$(wc -l < "$TMP/added")"
printf 'REMOVED  : %5d\n' "$(wc -l < "$TMP/removed")"
printf 'MODIFIED : %5d\n' "$(wc -l < "$TMP/modified")"
printf 'ADDED, excluding the vendored Realtek WiFi trees (class E): %s\n' \
       "$(grep -vc '^drivers/net/wireless/realtek/' "$TMP/added" || true)"
echo "--- ADDED (non-Realtek):";  grep -v '^drivers/net/wireless/realtek/' "$TMP/added" | sed 's/^/    /'
echo "--- REMOVED:";              sed 's/^/    /' "$TMP/removed"
echo "--- MODIFIED:";             sed 's/^/    /' "$TMP/modified"

# --------------------------------------------------------------------------
say "4. Commit list (provenance) -- everything after the version bump"
git -C "$FORK" log --reverse --format='%h|%ad|%an|%s' --date=short "$BASE..HEAD" > "$TMP/commits"
printf 'commits after the bump: %s   (PLAN.md sec 4.1 says "~60" -- it is wrong)\n' "$(wc -l < "$TMP/commits")"

: > "$TMP/commit-files"
while IFS='|' read -r h _ _ _; do
    git -C "$FORK" show --pretty=format: --name-only -m --first-parent "$h" \
        | grep -v '^$' | sed "s|^|$h\t|" >> "$TMP/commit-files"
done < "$TMP/commits"
cut -f2 "$TMP/commit-files" | sort -u > "$TMP/touched"

# --------------------------------------------------------------------------
say "5. Reconciliation (content diff <-> commit list, both directions)"
cat "$TMP/added" "$TMP/removed" "$TMP/modified" | sort -u > "$TMP/diffed"

echo "[A] In the content diff but touched by NO commit"
echo "    (expect: exactly the 11 import artefacts from step 2)"
comm -23 "$TMP/diffed" "$TMP/touched" | sed 's/^/    /'

echo "[B] Touched by a commit but NOT in the final diff -- transient (added-then-deleted /"
echo "    modified-then-reverted). Expect: Realtek files superseded by the morrownr backport,"
echo "    plus fs/exfat/exfat_config.h."
comm -13 "$TMP/diffed" "$TMP/touched" > "$TMP/transient"
printf '    count: %s\n' "$(wc -l < "$TMP/transient")"
printf '    under drivers/net/wireless/realtek/: %s\n' \
       "$(grep -c '^drivers/net/wireless/realtek/' "$TMP/transient" || true)"
echo "    outside Realtek:"
grep -v '^drivers/net/wireless/realtek' "$TMP/transient" | sed 's/^/        /'

say "Done. Cross-check against docs/patch-provenance.md sec 1."
