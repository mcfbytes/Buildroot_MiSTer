**Title:** fbdev: fix memremap() failure check in MiSTer_fb probe

**Body:**

`fb_probe()` maps the FPGA framebuffer window with `memremap()` and checks
the result with `IS_ERR()`, logging `"devm_ioremap_resource fb failed"` on
failure. `memremap()` returns `NULL` on failure, not an `ERR_PTR` — it's a
plain `void *`, and nothing in its implementation ever returns an encoded
error pointer. `IS_ERR(NULL)` is false and `PTR_ERR(NULL)` is 0, so this
check can never catch a real failure: `probe()` would return 0 (success)
with `fb_base` left `NULL`, and later dereferences (`pseudo_palette`,
`screen_base`, the close-time `memset()`) would fault instead of a clean
probe error. The log string also names a function that isn't the one
called here — reads like a leftover from an abandoned refactor.

**Why stock 5.15 users expect it:** not a stock-parity item — a plain
correctness bug in this branch's own independently-forward-ported driver.
Severity is low in practice (the FPGA framebuffer window is a fixed
DTB-asserted region; `memremap()` failing there is exceptional), but it's a
two-line, zero-risk fix.

**What Main_MiSTer depends on:** nothing — kernel-internal robustness only.

**How tested:** `patch -p1 -F0`/`git am` clean (0 offset) alone and in
sequence on `c129b0fac`. `MiSTer_fb.o` cross-compiled `ARCH=arm LLVM=1 W=1`
— zero warnings, before and after.

**Evidence:** Buildroot_MiSTer's own port of this driver
(`0001-fbdev-add-MiSTer_fb-driver.patch`) already uses the correct form;
documented as bug "B2" in that repo's `README.md`.
