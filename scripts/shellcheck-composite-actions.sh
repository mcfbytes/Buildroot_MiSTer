#!/usr/bin/env bash
#
# scripts/shellcheck-composite-actions.sh — run shellcheck over the `run:`
# bodies inside every .github/actions/*/action.yml composite action.
#
# (This file's own name is deliberately not repeated at the start of a
# comment line anywhere below. shellcheck recognizes a directive comment by
# its first two words alone -- "shellcheck" right after the "#" -- and does
# not require a well-formed key=value after that to start trying to parse
# one; a hash-mark comment beginning that way for any OTHER reason still
# trips its parser, SC1073/SC1072, confirmed by running shellcheck against
# this very file. So that two-word opening is reserved for actual
# directives here, never for prose.)
#
# WHY THIS EXISTS
# ---------------
# actionlint's own shellcheck integration checks `run:` blocks at WORKFLOW
# level, but does NOT descend into a locally-referenced composite action's
# `runs.steps[].run` bodies (verified against actionlint 1.7.7 -- see
# .github/workflows/lint.yml's header for the full writeup). That left every
# composite action under .github/actions/*/action.yml shellchecked by nothing:
# ~459 lines of shell across buildroot-build, kernel-leg,
# merge-kernel-modules and verify-image. This script is that missing check.
#
# There is no `actionlint --format-composite-as-script` or similar -- a
# composite action's `run:` step is just a YAML string, so getting shell text
# out of it means parsing the YAML ourselves. That is done with python3+yaml
# rather than sed/awk: a `run: |` block's exact text (dedented, newlines
# preserved) is exactly what a YAML parser is FOR, and reimplementing YAML
# block-scalar folding with sed to save a python3 dependency (already
# mandatory for this build -- see buildroot-build's apt list) would be a
# second, worse YAML parser.
#
# THINGS A NAIVE EXTRACTION GETS WRONG
# -------------------------------------
#   1. Shell dialect + already-active flags. Every composite `run:` step in
#      this repo declares `shell: bash`, and GitHub invokes it as
#          bash --noprofile --norc -eo pipefail {0}
#      i.e. -e and -o pipefail (NOT -u -- GitHub does not set that) are
#      already in effect before the extracted body's own first line runs.
#      Shellchecking the raw body with no such context would make shellcheck
#      reason as if NONE of that error handling exists, which does not match
#      what actually executes and can both over- and under-report. So each
#      extracted file gets `set -eo pipefail` prepended -- not a guess, the
#      literal invocation GitHub documents for composite `shell: bash` steps
#      -- before the real body, whether or not that body ALSO sets its own
#      (some do, e.g. for `-u`, which genuinely adds something the wrapper
#      doesn't). A future step with a different `shell:` value does not abort
#      the whole run (see the Exit section below): its body is skipped, an
#      ::error:: is recorded, and every OTHER extracted body still gets
#      checked in the same pass.
#   2. `${{ ... }}` expressions are not shell. GitHub substitutes them into
#      the step's script TEXT before bash ever sees it -- they are template
#      syntax, not a shell construct, and handing shellcheck a literal
#      `${{ inputs.foo }}` would either be a syntax error or, worse, silently
#      parse as something it isn't. Every action.yml in this repo instead
#      routes caller input through `env:`, precisely to keep `run:` bodies
#      plain, checkable bash (see buildroot-build's "Install build
#      dependencies" step comment) -- that is a convention, not something
#      YAML enforces, so a `run:` body that DOES interpolate `${{ ... }}`
#      directly is treated as a hard error here (an ::error:: naming the
#      file/step, exit 1) rather than being silently neutered into a
#      placeholder token and passed through clean. The placeholder
#      substitution still happens (so the rest of the body still gets
#      checked even when the violation is present), it just no longer
#      hides the violation itself.
#   3. Line numbers. shellcheck only ever sees the extracted temp file, never
#      action.yml, so a raw "line N" is meaningless to a reader (N counts
#      from the top of a synthetic wrapper this script invented, in a file
#      that a `trap ... EXIT` used to delete before anyone could open it).
#      Every `In <tmpfile> line N:` header shellcheck prints is rewritten,
#      below, back to the real `<action.yml> line M:` using the YAML
#      block-scalar's own start position (recorded via `yaml.compose`, which
#      preserves node marks that `yaml.safe_load` throws away) -- see the
#      extraction phase for the exact line math, which also has to account
#      for #1's synthetic `set -eo pipefail` line and for a body that starts
#      with its own leading blank/comment lines (a file-scope shellcheck
#      directive among them, which needs to land BEFORE that synthetic line
#      to keep file scope -- confirmed empirically: `set -eo pipefail`
#      followed by `# shellcheck disable=...` demotes it to a no-op, because
#      the directive is no longer the first thing in the file).
#   4. Sourcing scripts/ci-lib.sh. kernel-leg's `run:` steps source it with a
#      plain, repo-root-relative `source scripts/ci-lib.sh` (correct at
#      actual runtime -- GitHub always starts a composite `run:` step with
#      CWD = $GITHUB_WORKSPACE). But each step here is extracted into its
#      OWN file under $WORKDIR, an unrelated temp directory, so a bare
#      `shellcheck` run from there cannot find "scripts/ci-lib.sh" relative
#      to either the temp file's directory OR shellcheck's own CWD unless
#      that CWD is also the real repo root. Confirmed empirically: even
#      with a correct `# shellcheck source=scripts/ci-lib.sh` directive,
#      `-x` is REQUIRED for shellcheck to follow it at all (SC1091
#      otherwise, "was not specified as input"), and separately, `-x`
#      itself resolves a relative source= path against shellcheck's CWD,
#      not the checked file's directory -- so the shellcheck invocation
#      below runs with CWD explicitly pinned to $ROOT (this repo's root),
#      matching the one real filesystem layout "scripts/ci-lib.sh" is ever
#      correct against, rather than relying on this script always being
#      invoked from there (true today, per lint.yml and this header's own
#      Usage section, but not worth the silent breakage if that ever
#      changed).
#
# Usage: scripts/shellcheck-composite-actions.sh [action.yml ...]
#   Defaults to every action.yml/action.yaml found anywhere under
#   .github/actions/ (recursive, both spellings -- see the discovery step
#   below for why a one-level `*/action.yml` glob is not enough). Any path
#   may be passed for a targeted run (e.g. while editing just one action).
#
# Exit: 0 = every extracted `run:` body passed shellcheck (or there were none
#           to check -- an empty composite action is not a shellcheck failure).
#       1 = shellcheck found something, an action.yml could not be parsed, a
#           step declared a `shell:` other than "bash" (this script only
#           knows how to check bash; it refuses to mis-check it as bash, but
#           does not let that abort checking every OTHER step), or a `run:`
#           body interpolated `${{ ... }}` directly instead of going through
#           `env:`.
#       2 = usage / environment error (python3, PyYAML or shellcheck missing,
#           or no action.yml/action.yaml found at all).
#
# On any non-zero exit, the workdir holding the extracted .sh files and the
# raw (pre-remap) shellcheck output is left in place and its path is printed
# -- see the trap below for why that only used to happen on success.

set -euo pipefail

prog=${0##*/}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

die_usage() { echo "$prog: $*" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 || die_usage "python3 not found on PATH"
command -v shellcheck >/dev/null 2>&1 || die_usage "shellcheck not found on PATH"
python3 -c 'import yaml' 2>/dev/null ||
	die_usage "python3's yaml module (PyYAML) is not importable -- 'import yaml' failed. GitHub-hosted Ubuntu runners ship it as a dependency of cloud-init; a local checkout may need 'pip install pyyaml' or 'apt-get install python3-yaml'."

if [ "$#" -gt 0 ]; then
	files=("$@")
else
	# find, not a `.github/actions/*/action.yml` glob: depth- and
	# extension-agnostic on purpose. A one-level glob silently misses both a
	# nested composite action (.github/actions/group/sub/action.yml -- a
	# legal `uses: ./...` target) and the equally-valid `action.yaml`
	# spelling, and does so with the gate still reporting green ("...from 4
	# action.yml file(s)") -- exactly the coverage gap this script exists to
	# close, reopened by its own default. Same `mapfile -d '' ... -print0`
	# idiom lint.yml's own `find scripts -name '*.sh'` step already uses, for
	# the identical reason (that step's comment calls out that a non-recursive
	# glob would silently skip subdirectories). `sort -z` for a stable,
	# reproducible order across filesystems.
	mapfile -d '' -t files < <(find "$ROOT/.github/actions" \( -name 'action.yml' -o -name 'action.yaml' \) -print0 | sort -z)
fi

if [ "${#files[@]}" -eq 0 ]; then
	die_usage "no action.yml/action.yaml files found under $ROOT/.github/actions"
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/shellcheck-composite-actions.XXXXXX")"
# Cleaned up ONLY on a clean (exit 0) run. The extracted .sh files and the raw
# check output are the only way to inspect what actually got checked, and
# an unconditional `rm -rf` on every EXIT (the old behaviour) meant the exact
# path a failing run's own log just printed was already gone by the time
# anyone tried to open it -- confirmed by reproduction. A failing run instead
# leaves $WORKDIR in place and says so.
#
# A function, not an inline `trap '...' EXIT` string: shellcheck (confirmed
# empirically, independent of variable name) mis-flags SC2154 "referenced but
# not assigned" on a `$?`-capturing variable that is both assigned AND used
# inside the trap string itself, even though it plainly is assigned first.
# A named function sidesteps that false positive entirely.
# shellcheck disable=SC2329 # invoked indirectly via `trap cleanup EXIT` below
cleanup() {
	local rc=$?
	if [ "$rc" -eq 0 ]; then
		rm -rf "$WORKDIR"
	else
		echo "$prog: leaving $WORKDIR in place for inspection (run did not pass)" >&2
	fi
}
trap cleanup EXIT

# --- Extraction phase: one temp .sh file per `run:` step --------------------
# Printed to stdout, one path per line, collected into $WORKDIR/.filelist.
# A side channel, $WORKDIR/.manifest.tsv, records what each extracted file's
# lines actually correspond to in the source action.yml, so the remap phase
# further down can translate shellcheck's line numbers back to something a
# reader can open and believe.
#
# NOT `mapfile -t extracted < <(python3 ...)`: a failing command inside a
# process substitution does not trip `set -e` (mapfile itself still
# "succeeds"), which would silently swallow exactly the fail-loud errors
# (bad YAML, a non-bash `shell:`) the python side exists to report. Running
# it as a plain redirected command inside an `if`, and recording its status
# rather than exiting immediately on failure, is what lets every OTHER
# extracted body still get shellchecked in the same pass (see the Exit
# section above) instead of the whole gate aborting on the first
# unshellcheckable step.
extract_rc=0
if ! python3 - "$WORKDIR" "${files[@]}" > "$WORKDIR/.filelist" <<'PYEOF'
import os
import re
import sys

import yaml

workdir = sys.argv[1]
action_paths = sys.argv[2:]

# GitHub's own composite `shell: bash` invocation (documented, not guessed):
# https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions#exit-codes-and-error-action-preference
# -e and -o pipefail are ALREADY active by the time the step's own first line
# runs; -u is NOT set. Mirroring that exactly (not "set -euo pipefail", which
# would silently add -u nothing in this repo relies on) keeps the linter's
# dataflow analysis honest about what really executes.
#
# HEAD is this script's own explanatory wrapper -- never part of the body.
# The body's own leading run of blank/comment lines (a file-scope shellcheck
# directive among them) is re-emitted BETWEEN head and the synthetic
# `set -eo pipefail` line, not after it: shellcheck only treats a directive as
# FILE-scoped when nothing but comments/blanks precede it, and confirmed by
# reproduction, `set -eo pipefail` followed by `# shellcheck disable=...`
# demotes that directive to line-scope (covering only the next statement),
# silently making it inert for everything after. The line-remap math below
# depends on exactly this split, so if you touch one, touch the other.
HEAD = (
    "#!/usr/bin/env bash\n"
    "#\n"
    "# Extracted from {rel}, step {idx} (\"{name}\").\n"
    "# GitHub invokes a composite 'shell: bash' step as:\n"
    "#   bash --noprofile --norc -eo pipefail {{0}}\n"
    "# -- set -eo pipefail below mirrors that (no -u: GitHub doesn't set it\n"
    "# either), so shellcheck sees the same error-handling posture bash\n"
    "# actually runs this under, not a bare, unguarded script. Any leading\n"
    "# blank/comment lines of the body itself come next, BEFORE that set --\n"
    "# so a file-scope shellcheck directive at the top of the body keeps\n"
    "# file scope here too.\n"
)
SET_LINE = "set -eo pipefail\n"

# `${{ ... }}` is GitHub Actions expression syntax, substituted into the
# script TEXT before bash ever sees it -- not shell. Every action.yml in this
# repo instead routes caller input through `env:` (see buildroot-build's
# "Install build dependencies" step), precisely so `run:` bodies stay plain,
# shellcheckable bash -- but that is a convention this script must ENFORCE,
# not just assume: a body that violates it is flagged as an ::error:: below.
# The placeholder substitution still runs afterwards regardless, so the rest
# of a violating body is still shellchecked in the same pass rather than
# being skipped outright.
# Non-greedy and DOTALL: GitHub Actions expressions do not nest `{{`/`}}`,
# so the first `}}` always closes the expression that opened at the
# matched `${{`.
GHA_EXPR = re.compile(r"\$\{\{.*?\}\}", re.DOTALL)
PLACEHOLDER = "GHA_EXPR_PLACEHOLDER"


def slug(name, idx):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return (s[:60] or "step") + f"-{idx:02d}"


def leading_comment_run(body):
    """Split body's leading blank/`#`-only lines from the rest. Returns
    (head_text, rest_text); head_text is "" if body has no such lines."""
    lines = body.splitlines(keepends=True)
    i = 0
    while i < len(lines) and (lines[i].strip() == "" or lines[i].lstrip().startswith("#")):
        i += 1
    return "".join(lines[:i]), "".join(lines[i:])


def run_key_start_lines(path):
    """0-indexed line of each step's `run:` KEY (not its value) via
    yaml.compose, which preserves node marks that yaml.safe_load discards.
    Returns {step_index: line}; a step with no `run:` key, or any composing
    problem, is simply absent -- callers must treat a missing entry as
    "no source line available", never guess."""
    try:
        with open(path, encoding="utf-8") as f:
            root = yaml.compose(f, Loader=yaml.SafeLoader)
    except yaml.YAMLError:
        return {}

    def mapping_get(map_node, key):
        if map_node is None or not hasattr(map_node, "value"):
            return None
        for k, v in map_node.value:
            if getattr(k, "value", None) == key:
                return v
        return None

    runs_node = mapping_get(root, "runs")
    steps_node = mapping_get(runs_node, "steps")
    if steps_node is None or not hasattr(steps_node, "value"):
        return {}
    out = {}
    for i, step_node in enumerate(steps_node.value):
        run_node = mapping_get(step_node, "run")
        if run_node is not None:
            out[i] = run_node.start_mark.line
    return out


def tsv_field(s):
    # Manifest is TSV; a step name or path is never expected to contain a tab
    # or newline, but a defensive replace costs nothing and keeps a stray one
    # from corrupting every column after it.
    return s.replace("\t", " ").replace("\n", " ")


exit_code = 0
written = []
manifest_lines = []

for path in action_paths:
    rel = os.path.relpath(path, start=os.getcwd())
    try:
        with open(path, encoding="utf-8") as f:
            doc = yaml.safe_load(f)
    except OSError as e:
        print(f"::error::{rel}: could not read file: {e}", file=sys.stderr)
        exit_code = 1
        continue
    except yaml.YAMLError as e:
        print(f"::error::{rel}: could not parse YAML: {e}", file=sys.stderr)
        exit_code = 1
        continue

    steps = ((doc or {}).get("runs") or {}).get("steps") or []
    action_name = os.path.basename(os.path.dirname(path))
    run_lines = run_key_start_lines(path)

    for idx, step in enumerate(steps):
        if "run" not in step:
            continue  # a `uses:` step -- nothing to shellcheck

        name = step.get("name", f"step{idx}")
        shell = step.get("shell")
        if shell != "bash":
            print(
                f"::error::{rel}: step {idx} (\"{name}\") declares "
                f"shell={shell!r}, not 'bash' -- this script only knows how "
                "to shellcheck bash; refusing to silently mis-check it as "
                "bash, or to silently skip it. Every OTHER step is still "
                "checked.",
                file=sys.stderr,
            )
            exit_code = 1
            continue

        body = step["run"]
        if not isinstance(body, str):
            print(
                f"::error::{rel}: step {idx} (\"{name}\") has a non-string "
                "'run:' value -- action.yml is malformed.",
                file=sys.stderr,
            )
            exit_code = 1
            continue

        if GHA_EXPR.search(body):
            found = GHA_EXPR.search(body).group(0)
            print(
                f"::error::{rel}: step {idx} (\"{name}\") interpolates a "
                f"'${{{{ ... }}}}' expression directly inside its 'run:' body "
                f"({found!r}) -- this repo's convention is to route caller "
                "input through 'env:' instead (see buildroot-build's "
                "\"Install build dependencies\" step), keeping 'run:' bodies "
                "plain, shellcheckable bash and avoiding the classic Actions "
                "script-injection footgun. The expression is still replaced "
                "with a placeholder below so the rest of the body is still "
                "shellchecked, but this occurrence itself is a failure.",
                file=sys.stderr,
            )
            exit_code = 1
        body = GHA_EXPR.sub(PLACEHOLDER, body)
        if not body.endswith("\n"):
            body += "\n"

        head_text = HEAD.format(rel=rel, idx=idx, name=name)
        head_lines = len(head_text.splitlines())
        leading_text, rest_text = leading_comment_run(body)
        leading_lines = len(leading_text.splitlines())

        out_name = f"{action_name}__{slug(name, idx)}.sh"
        out_path = os.path.join(workdir, out_name)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(head_text)
            f.write(leading_text)
            f.write(SET_LINE)
            f.write(rest_text)
        written.append(out_path)

        run_line0 = run_lines.get(idx, -1)
        manifest_lines.append(
            "\t".join(
                [
                    out_path,
                    tsv_field(rel),
                    str(idx),
                    tsv_field(name),
                    str(run_line0),
                    str(head_lines),
                    str(leading_lines),
                ]
            )
        )

with open(os.path.join(workdir, ".manifest.tsv"), "w", encoding="utf-8") as f:
    f.write("\n".join(manifest_lines) + ("\n" if manifest_lines else ""))

for p in written:
    print(p)

sys.exit(exit_code)
PYEOF
then
	extract_rc=1
fi
mapfile -t extracted < "$WORKDIR/.filelist"

if [ "$extract_rc" -ne 0 ]; then
	echo "$prog: extraction reported problem(s) above -- checking every other extracted body anyway, then failing" >&2
fi

if [ "${#extracted[@]}" -eq 0 ]; then
	if [ "$extract_rc" -ne 0 ]; then
		exit 1
	fi
	echo "$prog: no 'run:' steps found under ${files[*]} -- nothing to check"
	exit 0
fi

echo "$prog: shellchecking ${#extracted[@]} extracted run: bod$([ "${#extracted[@]}" -eq 1 ] && echo y || echo ies) from ${#files[@]} action.yml/action.yaml file(s)"

shellcheck_rc=0
# CWD pinned to $ROOT (a subshell, so the parent script's own CWD is
# untouched) -- see item 4 in the header above: `-x` is required to follow
# the `source scripts/ci-lib.sh` some extracted steps now contain, and `-x`
# resolves that relative path against shellcheck's CWD, not against
# $WORKDIR where the extracted files actually live.
if ! ( cd "$ROOT" && shellcheck -s bash -x "${extracted[@]}" ) > "$WORKDIR/.shellcheck.out" 2>&1; then
	shellcheck_rc=1
fi

# --- Remap phase: rewrite "In <tempfile> line N:" back to the real
# action.yml path + line, using $WORKDIR/.manifest.tsv from the extraction
# phase. Anything shellcheck printed that is NOT one of those headers (the
# code snippet, the caret, the SC number, the "Did you mean" block) passes
# through unchanged -- only the header line names a temp file at all.
python3 - "$WORKDIR/.manifest.tsv" "$WORKDIR/.shellcheck.out" <<'PYEOF2'
import re
import sys

manifest_path, sc_out_path = sys.argv[1], sys.argv[2]

info = {}
try:
    with open(manifest_path, encoding="utf-8") as f:
        for raw in f:
            raw = raw.rstrip("\n")
            if not raw:
                continue
            parts = raw.split("\t")
            if len(parts) != 7:
                continue
            out_path, rel, idx, name, run_line0, head_lines, leading_lines = parts
            info[out_path] = {
                "rel": rel,
                "idx": idx,
                "name": name,
                "run_line0": int(run_line0),
                "head_lines": int(head_lines),
                "leading_lines": int(leading_lines),
            }
except OSError:
    info = {}

HEADER_RE = re.compile(r"^In (\S+) line (\d+):$")


def remap(meta, lineno):
    """See the extraction phase's HEAD/SET_LINE comment for the file shape
    this mirrors: HEAD (head_lines), then the body's own leading
    blank/comment run (leading_lines), then the synthetic `set -eo pipefail`
    line, then the rest of the body. Returns the action.yml line, or None if
    `lineno` falls in one of this script's own synthetic lines rather than
    in the actual `run:` body."""
    p0 = meta["head_lines"]
    lh = meta["leading_lines"]
    pre = p0 + lh + 1  # + the synthetic `set -eo pipefail` line
    if lineno <= p0 or lineno == pre:
        return None
    if lineno <= p0 + lh:
        body_line = lineno - p0
    else:
        body_line = (lineno - pre) + lh
    return meta["run_line0"] + 1 + body_line


try:
    with open(sc_out_path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = HEADER_RE.match(line)
            if not m:
                print(line)
                continue
            path, lineno = m.group(1), int(m.group(2))
            meta = info.get(path)
            mapped = None
            if meta is not None and meta["run_line0"] >= 0:
                mapped = remap(meta, lineno)
            if meta is None or mapped is None:
                # No manifest entry, or the line is one of this script's own
                # synthetic wrapper lines (or yaml.compose could not recover
                # a source line) -- print shellcheck's original header rather
                # than assert a mapping we cannot back up.
                print(line)
                continue
            print(
                f'In {meta["rel"]} line {mapped}: '
                f'(step {meta["idx"]} "{meta["name"]}"; '
                f"extracted: {path}:{lineno})"
            )
except OSError as e:
    print(f"shellcheck-composite-actions.sh: could not read shellcheck output: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF2

if [ "$extract_rc" -ne 0 ] || [ "$shellcheck_rc" -ne 0 ]; then
	exit 1
fi
exit 0
