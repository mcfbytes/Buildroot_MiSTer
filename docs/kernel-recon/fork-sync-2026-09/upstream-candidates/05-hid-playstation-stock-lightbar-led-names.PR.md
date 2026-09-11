**Title:** dualsense: restore stock lightbar LED names

**Body:**

Both PlayStation pads on this branch silently lose lightbar colour control
from Main_MiSTer. DualSense: this branch exposes only one multicolor LED
(`"inputN:rgb:indicator"`, `multi_intensity`) — stock additionally exposes
three plain LEDs, `"<hid-dev>:red/:green/:blue"`. DualShock 4: this branch's
`ps_led_register()` names its "hid-sony-compatible" branch (the one DS4
uses) from the *input* device (`"inputN:red"`) instead of the HID device.

**Why stock 5.15 users expect it:** Main_MiSTer writes the three colour
paths directly, keyed off the HID device — DualSense once its `":player_id"`
LED succeeds (this branch's own `ds_leds_create()` already provides that),
DS4 via its fallback branch. Neither reaches a target under this branch's
current naming, so both pads sit on their driver-default colour forever,
with nothing logged.

**Two changes:** (1) `ps_led_register()`'s hid-sony-compatible branch names
from the HID device, scoped to that one branch only. (2)
`dualsense_create()` additionally registers three plain lightbar LEDs beside
the existing multicolor device, via a small `struct dualsense_rgb_led`
carrying its own device+index (a fixed-array `container_of()` would
silently miscompute the base for green/blue). This branch's own
`ds_leds_create()` already clears the player-LED row at probe, so no change
needed there.

**How tested:** `patch -p1 -F0`/`git am` clean (0 offset) alone and in
sequence on `c129b0fac`. `hid-playstation.o` cross-compiled `ARCH=arm
LLVM=1 W=1` — no new warnings (one pre-existing, unrelated `err_free`
unused-label warning present before and after). **Not bench-verified** —
needs a DualSense and a DS4.

**Evidence:** Buildroot_MiSTer
`docs/kernel-recon/records/f84543926371d7911bff2d3a12daa5d325e4c2d9.json`
(same origin commit family, carried as `0042` in that repo's own series).
