# Beta-Tester Guide (STUB — P4.10)

**Status:** Placeholder. This stub was created by P4.9 (community & governance files); the full beta-testing guide lands with **P4.10 (Beta launch)**, which is gated on the ADR 0014 sustainability sign-off.

---

## What does "beta" mean?

This image is **personal-use only** until a named maintainer commits to tracking kernel security updates (ADR 0014). The image has been validated on one DE10-Nano board during Phase 3 hardware testing. Expect:

- ✅ The kernel boots and the stock `MiSTer` binary runs
- ✅ USB controllers, Bluetooth, and WiFi devices are supported
- ✅ Audio and video output work
- ⚠️ Some edge cases, device-specific issues, or undiscovered regressions
- ⚠️ No guaranteed support or maintenance windows

---

## Opting In

**Coming in P4.10:** Instructions for joining the beta-tester cohort, including:
- How to download the beta image
- How to report issues via the bug tracker
- Expected SLAs and communication channels
- When and how to roll back to the stock image

---

## Reporting Issues

Found a bug? Open an issue using the **Bug Report** template:
- Include your `MiSTer.version` (first 6 bytes of `/MiSTer.version`)
- Capture kernel output via serial console if possible
- Describe the steps to reproduce

For hardware compatibility reports, use the **Hardware Test Report** template.

See `CONTRIBUTING.md` for detailed submission guidelines.

---

## How to Roll Back

**Coming in P4.10:** Step-by-step instructions for reverting to the stock image if needed.

---

## Next Steps

P4.10 will finalize:
- Exact testing window and success criteria
- Beta-tester roster and responsibilities
- Weekly status digest template
- Rollback procedures
- Publication gate sign-off

See `TASKS.md` for the full Phase 4 plan.
