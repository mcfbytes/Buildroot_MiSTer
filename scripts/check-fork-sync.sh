#!/usr/bin/env bash
#
# check-fork-sync.sh — report fork commits we have not reconciled yet.
#
# Diffs docs/kernel-recon/fork-sync.conf (the last reconciled commit per fork branch)
# against MiSTer-devel/Linux-Kernel_MiSTer's live HEADs, and prints what has landed since.
# That list is the backport queue: each commit needs a disposition -- carried into
# board/mister/de10nano/linux-patches/, carried into
# board/mister/de10nano/linux-patches-upstream/ (the exported tree needs it but our image
# does not), or recorded as deliberately dropped with a reason. The disposition itself is a
# record at docs/kernel-recon/records/<full-sha>.json; docs/patch-provenance.md is the
# pre-2026-07 campaign's table and is history, not the destination for new work.
#
# Read fork-sync.conf's header for why this exists at all; the short version is that
# nothing else ever forces the question, and the fork sat on 5.15.1 for 210 stable
# releases partly because of that.
#
# Cheap by construction: one compare API call per branch, no clone. The kernel repo is
# ~300MB and there is no reason to fetch it to answer "what is new".
#
# Usage: scripts/check-fork-sync.sh [--markdown]
#   --markdown   emit a GitHub-flavoured report (used by the workflow for issue bodies)
#
# Exit: 0 = fully reconciled; 1 = commits need triage (report on stdout); 2 = error.
#       The workflow keys off 1 vs 0, so do not make drift fatal-looking; it is normal.

set -o errexit
set -o nounset
set -o pipefail

# Assigned then marked readonly separately: `readonly X="$(cmd)"` masks cmd's exit status
# (shellcheck SC2155), and the rest of scripts/ avoids that pattern.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly CONF="$REPO_ROOT/docs/kernel-recon/fork-sync.conf"
readonly FORK="${FORK_REPO:-MiSTer-devel/Linux-Kernel_MiSTer}"

markdown=false
[[ ${1:-} == --markdown ]] && markdown=true

err() { printf 'check-fork-sync: %s\n' "$*" >&2; }

command -v gh >/dev/null || { err 'gh CLI not found'; exit 2; }
command -v jq >/dev/null || { err 'jq not found (this script parses the compare API with it)'; exit 2; }
[[ -f $CONF ]] || { err "no such file: $CONF"; exit 2; }

drift=0
report=''

# One line per branch: "<branch> <sha>". Comments and blanks stripped.
while read -r branch sync; do
	[[ -n ${branch:-} ]] || continue

	[[ ${#sync} -eq 40 ]] || { err "$branch: sync point must be a full 40-char SHA, got '$sync'"; exit 2; }

	# compare gives us ahead_by + the commit list without cloning anything. `...` is
	# three-dot on purpose: we want commits reachable from the branch but not from the
	# sync point, which is exactly "what landed since we last looked".
	if ! cmp_json="$(gh api "repos/$FORK/compare/$sync...$branch" 2>/dev/null)"; then
		# A missing branch is worth failing on: it means the fork restructured and this
		# file is now describing something that does not exist.
		err "cannot compare $sync...$branch in $FORK (branch gone, or SHA not an ancestor?)"
		exit 2
	fi

	ahead="$(jq -r '.ahead_by' <<<"$cmp_json")"

	# Insist on an integer before comparing. This is not defensive padding: bash
	# arithmetic treats a bare word as an unset variable, so BOTH `[[ null -eq 0 ]]` and
	# `[[ "" -eq 0 ]]` evaluate TRUE. A response that parsed but had no ahead_by -- an
	# auth failure, a rate limit, a partial body -- would therefore report "nothing new"
	# and exit 0. A tool whose entire job is to stop commits going unaccounted for must
	# not have a path where it silently says all-clear because it could not tell.
	[[ $ahead =~ ^[0-9]+$ ]] || {
		err "$branch: compare API returned no usable ahead_by (got '$ahead')."
		err "Refusing to report 'reconciled' from a response we cannot read."
		exit 2
	}

	if [[ $ahead -eq 0 ]]; then
		if $markdown; then
			report+="- ✅ \`$branch\` — reconciled through \`${sync:0:9}\`, nothing new.
"
		else
			report+="  [ok]    $branch — reconciled through ${sync:0:9}, nothing new
"
		fi
		continue
	fi

	drift=$((drift + 1))
	if $markdown; then
		report+="
### \`$branch\` — $ahead commit(s) to triage

Reconciled through [\`${sync:0:9}\`](https://github.com/$FORK/commit/$sync). Since then:

| commit | subject | author | date |
|---|---|---|---|
"
		# Two rewrites on the subject, and the second one is not cosmetic. A subject
		# ends "(#92)" because that is how GitHub spells a merged PR -- but this text is
		# posted into an issue in THIS repo, where a bare #92 autolinks to THIS repo's
		# #92, a completely unrelated PR of ours. The number belongs to the FORK, so
		# qualify it into an explicit link there. Written as a markdown link rather than
		# the `owner/repo#92` shorthand so the cell still reads "#92"; being already a
		# link is also what stops GitHub autolinking it a second time. /issues/N is the
		# right endpoint for either kind -- GitHub redirects it to /pull/N when N is a
		# PR, so the script does not have to know which it is. "C#" and the like are
		# untouched: the pattern requires digits.
		# The pipe escape must stay FIRST -- an unescaped | ends the table cell.
		report+="$(jq -r --arg f "$FORK" '.commits[] |
			"| [`\(.sha[0:9])`](https://github.com/\($f)/commit/\(.sha)) | \(.commit.message | split("\n")[0] | gsub("\\|"; "\\\\|") | gsub("#(?<n>[0-9]+)"; "[#\(.n)](https://github.com/\($f)/issues/\(.n))")) | \(.commit.author.name) | \(.commit.author.date[0:10]) |"' <<<"$cmp_json")
"
	else
		report+="
  [TRIAGE] $branch — $ahead commit(s) since ${sync:0:9}
"
		report+="$(jq -r '.commits[] | "    \(.sha[0:9])  \(.commit.author.date[0:10])  \(.commit.message | split("\n")[0])"' <<<"$cmp_json")
"
	fi
done < <(grep -vE '^\s*(#|$)' "$CONF")

if $markdown; then
	if ((drift)); then
		printf '%s\n' "The fork has commits with no disposition in this repo. Each needs one of:

- **carried** → a patch in \`board/mister/de10nano/linux-patches/\`, which Buildroot applies to the image *and* the export replays, or
- **carried for upstream only** → a patch in \`board/mister/de10nano/linux-patches-upstream/\`, when the exported tree needs it but our image deliberately does not (see that directory's README), or
- **dropped** → a record saying so, and why (superseded upstream, packaged separately, obsolete…).

Either way the disposition is a structured record at \`docs/kernel-recon/records/<full-sha>.json\` — that is the current mechanism and the one to use. (\`docs/patch-provenance.md\` holds the pre-2026-07 campaign's rows; it is history, not where new work goes.)

Then advance the branch's line in \`docs/kernel-recon/fork-sync.conf\`.

> Advancing that file to silence this issue is the one thing that breaks the mechanism — it would stop meaning *reconciled* and start meaning *seen*.
$report"
	else
		printf '%s\n' "$report
Nothing to triage."
	fi
else
	printf '=== fork sync: %s\n%s\n' "$FORK" "$report"
	if ((drift)); then
		printf 'RESULT: %d branch(es) need triage — see docs/patch-provenance.md\n' "$drift"
	else
		printf 'RESULT: fully reconciled\n'
	fi
fi

((drift == 0))
