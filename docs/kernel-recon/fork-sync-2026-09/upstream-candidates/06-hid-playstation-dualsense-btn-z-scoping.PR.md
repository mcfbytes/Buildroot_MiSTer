**Title:** dualsense: scope BTN_Z to DualSense only

**Body:**

`ps_gamepad_buttons[]` — the shared capability table used by both
`dualsense_create()` and `dualshock4_create()` — currently lists `BTN_Z`.
That gives DualShock 4 the `BTN_Z` capability bit too, even though nothing
ever reports it for DS4: the only `input_report_key(..., BTN_Z, ...)` in the
file is `dualsense_parse_report()`, gated on `DS_BUTTONS2_MIC_MUTE`, a field
DS4's report format doesn't have.

**Why stock 5.15 users expect it:** stock's table never lists `BTN_Z`; it
declares the capability per-device in `dualsense_create()` instead. This
patch restores that scoping — remove it from the shared table, add
`input_set_capability(ds->gamepad, EV_KEY, BTN_Z)` in `dualsense_create()`.
Nothing about this branch's existing mic-mute→`BTN_Z` reporting or the
`":mute"` LED classdev changes; both already match stock intent here.

**Behavioural change for DS4 users:** after this patch, a DualShock 4's
evdev capability bitmap no longer advertises `BTN_Z`. Nothing ever reported
or consumed that bit for DS4 before or after, so no input a DS4 could
actually produce goes away — this removes a false capability advertisement,
not a working feature. No Main_MiSTer coupling either way: `BTN_Z`-as-mute
has no dedicated Main_MiSTer consumer on any pad (checked by grep); a user
can still hand-bind DualSense mute via the generic OSD button-remap screen,
unaffected by this patch.

**How tested:** `patch -p1 -F0`/`git am` clean (0 offset) alone and in
sequence on `c129b0fac`. `hid-playstation.o` cross-compiled `ARCH=arm
LLVM=1 W=1` — no new warnings.

**Evidence:** Buildroot_MiSTer
`docs/kernel-recon/records/60e08955fe23c2a1d57834f7dc31860395542e4a.json`
(same origin commit, carried as `0037` in that repo's own series).
