# Phase 0 report — canonical enumeration

Generated 2026-07-15 04:27 UTC by `phase0.py`.

- Fork HEAD (`MiSTer-v5.15`): `f0fb626acadd07f0718934826b143b6e4c9ce81c`
- Vanilla base: `v5.15.1` = `b6abb62daa5511c4a3eaa30cbdb02544d1f10fa2`
- Vanilla target: `v6.18.38` = `e46dc0adfe39724bcf52cea47b8f9c9aed86a394`
- Delta commits enumerated: **108** (113 total − 4 imports − 1 merge)

## Change-type histogram

| Type | Count |
|---|---|
| in-tree-code | 67 |
| out-of-tree-module | 15 |
| dts | 11 |
| kconfig | 11 |
| uapi-header | 2 |
| docs-or-build | 2 |

## Import purity (plan §3.2)

| Import | Tag | Tree identical? |
|---|---|---|
| `e12ed6c19` | `v5.13.12` | ⚠️ 9 files gitignored at import (benign) |
| `137491a75` | `v5.14` | ⚠️ 9 files gitignored at import (benign) |
| `b6f2ca1c4` | `v5.14.5` | ⚠️ 9 files gitignored at import (benign) |
| `aba1ef4c1` | `v5.15.1` | ⚠️ 11 files gitignored at import (benign) |

Residue detail — `missing-in-import` + an ignore rule means git skipped the
file when the extracted tarball was `git add`ed (kernel's own `.gitignore`);
no such file is part of the kernel build.

### Residue in `e12ed6c19`

- `Documentation/devicetree/bindings/.yamllint` — missing-in-import, rule `.gitignore:13:.*`
- `fs/ext4/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `lib/kunit/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `tools/testing/selftests/arm64/tags/.gitignore` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/Makefile` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/run_tags_test.sh` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/tags_test.c` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/bpf/test_progs.c` — missing-in-import, rule `tools/testing/selftests/bpf/.gitignore:12:/test_progs*`
- `tools/testing/selftests/tc-testing/plugins/__init__.py` — missing-in-import, rule `tools/testing/selftests/tc-testing/.gitignore:4:plugins/`

### Residue in `137491a75`

- `Documentation/devicetree/bindings/.yamllint` — missing-in-import, rule `.gitignore:13:.*`
- `fs/ext4/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `lib/kunit/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `tools/testing/selftests/arm64/tags/.gitignore` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/Makefile` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/run_tags_test.sh` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/tags_test.c` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/bpf/test_progs.c` — missing-in-import, rule `tools/testing/selftests/bpf/.gitignore:12:/test_progs*`
- `tools/testing/selftests/tc-testing/plugins/__init__.py` — missing-in-import, rule `tools/testing/selftests/tc-testing/.gitignore:4:plugins/`

### Residue in `b6f2ca1c4`

- `Documentation/devicetree/bindings/.yamllint` — missing-in-import, rule `.gitignore:13:.*`
- `fs/ext4/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `lib/kunit/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `tools/testing/selftests/arm64/tags/.gitignore` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/Makefile` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/run_tags_test.sh` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/tags_test.c` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/bpf/test_progs.c` — missing-in-import, rule `tools/testing/selftests/bpf/.gitignore:12:/test_progs*`
- `tools/testing/selftests/tc-testing/plugins/__init__.py` — missing-in-import, rule `tools/testing/selftests/tc-testing/.gitignore:4:plugins/`

### Residue in `aba1ef4c1`

- `Documentation/devicetree/bindings/.yamllint` — missing-in-import, rule `.gitignore:13:.*`
- `fs/ext4/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `fs/fat/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `lib/kunit/.kunitconfig` — missing-in-import, rule `.gitignore:13:.*`
- `tools/perf/include/perf/perf_dlfilter.h` — missing-in-import, rule `tools/perf/.gitignore:6:perf`
- `tools/testing/selftests/arm64/tags/.gitignore` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/Makefile` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/run_tags_test.sh` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/arm64/tags/tags_test.c` — missing-in-import, rule `.gitignore:116:tags`
- `tools/testing/selftests/bpf/test_progs.c` — missing-in-import, rule `tools/testing/selftests/bpf/.gitignore:12:/test_progs*`
- `tools/testing/selftests/tc-testing/plugins/__init__.py` — missing-in-import, rule `tools/testing/selftests/tc-testing/.gitignore:4:plugins/`

## Tree-diff completeness backstop (plan §3.3)

- Differing paths (fork HEAD vs `v5.15.1`): 3571 (3485 added, 48 modified, 38 deleted)
- Unattributed but explained (gitignored-at-import deletions): 11
- **Unattributed and unexplained: 0** (invariant HOLDS — every other differing path traces to an enumerated commit)
- Touched-but-reverted paths: 149 (informational)
- Out-of-tree dirs (absent from vanilla v5.15.1): `drivers/hid/xone`, `drivers/net/wireless/realtek/rtl8188eu`, `drivers/net/wireless/realtek/rtl8188fu`, `drivers/net/wireless/realtek/rtl8812au`, `drivers/net/wireless/realtek/rtl8821au`, `drivers/net/wireless/realtek/rtl8821cu`, `drivers/net/wireless/realtek/rtl88x2bu`

Hunk-level completeness follows from path attribution + import purity: the
`v5.15.1` import is byte-identical to vanilla except for gitignored file
*omissions* (no content changes), and the enumeration covers *every* commit
between that import and fork HEAD, so each differing path's content is fully
composed of enumerated commits.

## Already-upstream pre-filter (plan §3.4)

- vanilla candidate pool: 1766 commits patch-id'd (path-scoped, `v5.15.1..v6.18.38`); 334319 subjects compared (full range)
- patch-id matches (provisional `dropped-upstream (backport)`): **0**
- subject-only matches (hint, NOT a disposition): **0**

## Old-branch sweep (plan §3.5)

- MiSTer-v5.14: 61 branch-only, 55 matched, **6 residue** → appendix work list
- MiSTer-v5.13.12: 52 branch-only, 43 matched, **9 residue** → appendix work list

See `old-branch-residue.md` for the residue detail.
