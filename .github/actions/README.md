# CI Composite Actions

| Action | Owns | Called by | Notes |
|--------|------|-----------|-------|
| **buildroot-build** | Runner prep (disk, apt, five caches) + `make all` (main) or `make <variant>` (kernel-only). Outputs: `output/images/` or `output-<name>/images/` + legal-info on demand. | build.yml, release.yml, reproducibility.yml | Single source of truth for the Buildroot recipe across three workflows. main's cache key strings are byte-identical to before the variant input existed; existing cache entries keep hitting. Kernel variants derive their own cache namespaces from fragment existence. |
| **kernel-leg** | One kernel-variant matrix leg: build via buildroot-build, render job summary, stage artifact (zImage_dtb + .config + modules tar + legal-info), upload for `build` to merge. | build.yml (build-kernel matrix), release.yml (build-kernel matrix) | Moves the 72-identical shared lines from build.yml and release.yml's own copies. Inputs: kernel, full-legal-info, release-context. |
| **merge-kernel-modules** | Two phases: (1) phase=download: download kernel-leg artifacts, populate work/extra-modules-overlay/ (runs BEFORE buildroot-build); (2) phase=verify: assert every kver merged into output/target/ (runs AFTER buildroot-build). | build.yml, release.yml | Phase-gated input enforces sequence discipline and prevents silent overlay misses. Called twice per workflow (download then verify). |
| **verify-image** | Run parity suite (P3.12) + ABI/SONAME checker (P2.2) against built image. Uploads results artifact on every run (`if: always()`). | build.yml, release.yml | Input: skip-qemu-system (default "true" — byte-identical to old hard-coded "1"). Both workflows used to carry identical copies. |

## Rule: When to Add a Fifth Action

**Only add a new composite action when ALL of these hold:**
1. The work is genuinely self-contained (no dependencies within another action's phase).
2. Its failure modes are independent (a failure does NOT require coordination with an existing action's state).
3. No workflow sequence rule applies (if two actions must run in order with state between them, use a phase input instead — see `merge-kernel-modules`).

**Otherwise, extend an existing action via inputs.**

The trap this prevents: duplicating a step silently causes drift. Three copies of the same 85-line block → five bugs fixed in one, three still lurking elsewhere.
