**Title:** hid-nintendo: use stock button mapping for NSO N64 and Genesis pads

**Body:**

Re-maps the NSO N64 and Genesis/Mega Drive controllers' wire bits to the evdev
codes stock MiSTer 5.15 assigned, instead of mainline's assignment this branch
currently carries. N64: A/B swapped, three of four C-buttons moved. Genesis:
six of ten bits (A, C, X, Y, Z, Mode) moved. Only the code-set *sizes* matched
before this patch (13 and 10); the members didn't.

**Why stock 5.15 users expect it:** not a mainline oversight this repo is
restoring — a MiSTer-specific choice stock has shipped since 5.15, and one
this branch's own tables already use for every *other* NSO controller (SNES,
standard Joy-Con). N64/Genesis are the two outliers still on mainline's
layout. Traces to Linux-Kernel_MiSTer `b00a72159a` (2023-09-04) and
`2799f8b947` (2023-09-02), both Shig.

**What Main_MiSTer depends on:** `gamecontroller_db.cpp:207-217`
(`get_ctrl_index_maps()`) derives its `bN` indices as an ascending ordinal
walk over the kernel's `EV_KEY` bitmap — one moved code renumbers every
button after it. `.map` files store the raw evdev code directly. Both
mis-resolve silently on this branch today: no error, just a scrambled pad.

**How tested:** `patch -p1 -F0` and `git am`, both alone and in the full
7-candidate sequence, on a fresh `c129b0fac` checkout — clean, zero offset
applied alone. `drivers/hid/hid-nintendo.o` cross-compiled `ARCH=arm LLVM=1
W=1` against `MiSTer_defconfig` — no new warnings. Table contents checked
byte-for-byte against stock hid-nintendo.c's
`n64con_button_inputs[]`/`mdcon_button_inputs[]`. **Not bench-verified** —
needs a physical NSO N64 and NSO Genesis pad.

**Evidence:** Buildroot_MiSTer
`docs/kernel-recon/records/b00a72159aeb6996e1006d28383fdb8e2667746b.json`
(same origin commit, carried as `0039` in that repo's own series).
