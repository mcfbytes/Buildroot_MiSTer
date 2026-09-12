# CI Composite Actions

| Action | Owns | Called by | Notes |
|--------|------|-----------|-------|
| **buildroot-build** | Runner prep (disk, apt, caches) + `make all`. Outputs: `output/images/` (linux.img, zImage_dtb, zImage_dtb-rt, mister-initramfs.cpio) + legal-info on demand. Since ADR 0030 Phase C the RT kernel and the stage-1 initramfs are packages of the one build, so there is no kernel-only variant mode any more (the `variant` input errors on anything but `main`). | build.yml, release.yml, reproducibility.yml | Single source of truth for the Buildroot recipe across three workflows. main's cache key strings are byte-identical to before the variant input existed; existing cache entries keep hitting. Kernel variants derive their own cache namespaces from fragment existence. |
| **verify-image** | Run parity suite (P3.12) + ABI/SONAME checker (P2.2) against built image. Uploads results artifact on every run (`if: always()`). | build.yml, release.yml | Input: skip-qemu-system (default "true" — byte-identical to old hard-coded "1"). Both workflows used to carry identical copies. |

## Rule: When to Add a Fifth Action

**Only add a new composite action when ALL of these hold:**
1. The work is genuinely self-contained (no dependencies within another action's phase).
2. Its failure modes are independent (a failure does NOT require coordination with an existing action's state).
3. No workflow sequence rule applies (if two actions must run in order with state between them, use a phase input instead).

**Otherwise, extend an existing action via inputs.**

The trap this prevents: duplicating a step silently causes drift. Three copies of the same 85-line block → five bugs fixed in one, three still lurking elsewhere.
