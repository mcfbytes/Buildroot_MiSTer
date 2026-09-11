**Title:** hid-nintendo: keep the " IMU" suffix userspace filters on

**Body:**

The Joy-Con/Pro Controller registers a second input device for its
accelerometer/gyro. This branch names it `"%s (IMU)"` (mainline's form, from
`94f18bb19945`). Main_MiSTer's *only* hook for excluding this device from its
controller pool is `strstr(name, " IMU")` — no `INPUT_PROP`, no capability
check. `"(IMU)"` puts `(` right after the space, so the match fails.

**Why stock 5.15 users expect it:** stock's names are fixed literals ending
in `" IMU"` / `" IMU (Grip)"` (the literals themselves are mainline's own,
from `4ff5b10840a8`). Dropping the parenthesis restores the substring while
keeping this branch's derived-from-the-HID-name form — the minimal change,
not a full revert to the fixed literals.

**What Main_MiSTer depends on:** `input.cpp:6103`,
`strstr(input[n].name, " IMU")`. Without the match, the IMU node opens as an
ordinary controller: it takes a device-pool slot, streams `ABS_*` at IMU
rate, and can be auto-assigned as a player — a phantom controller, silently,
on every Joy-Con, Pro Controller and NSO pad.

**How tested:** `patch -p1 -F0` and `git am` clean (0 offset) alone and in
the 7-candidate sequence on `c129b0fac`. `hid-nintendo.o` cross-compiled
`ARCH=arm LLVM=1 W=1` — no new warnings. **Not bench-verified.**

**Evidence:** Buildroot_MiSTer
`docs/kernel-recon/records/45283785a7ace3263f7c165ae6a4ec3055ebdcf6.json`
(same origin commit family, carried as `0040` in that repo's own series).
