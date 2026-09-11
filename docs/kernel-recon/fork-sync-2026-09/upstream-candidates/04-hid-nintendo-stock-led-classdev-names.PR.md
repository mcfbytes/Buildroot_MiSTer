**Title:** hid-nintendo: restore stock LED classdev names

**Body:**

Every Switch controller on this branch silently loses userspace control of
its player-LED row and home LED. This branch, like mainline, names them
`"<hid-dev>:green:player-1"`..`-4"` and `"<hid-dev>:blue:player-5"` (the LED
class spec). Stock names them `"<hid-dev>:player1"`..`"player4"` and
`"<hid-dev>:home"`.

**Why stock 5.15 users expect it:** Main_MiSTer opens these by exact path
(`input.cpp:2761`, `update_num_hw()`: `set_led(led_path, ":home", ...)` and
`":player1"`..`":player4"`), and its `set_led()` treats a failed `fopen()`
as a silent no-op. Under this branch's current names, all five writes are
discarded with nothing logged: the player row keeps its connect-order
pattern forever, and the home LED never lights. The `":combo"` node a few
lines away in the same function already uses stock's naming and works —
that's why only these two nodes going silent was easy to miss.
`max_brightness` (1 and 0xF) already matches stock; only the name format
string changes.

**How tested:** `patch -p1 -F0` and `git am` clean (0 offset) alone and in
sequence on `c129b0fac`. `hid-nintendo.o` cross-compiled `ARCH=arm LLVM=1
W=1` — one new warning, `-Wunneeded-internal-declaration` on
`joycon_player_led_names[]` (its strings are no longer read at runtime, only
its `ARRAY_SIZE`; compile-time-only, no functional effect). **Not
bench-verified** — needs a Switch pad.

**Evidence:** Buildroot_MiSTer
`docs/kernel-recon/records/60821059c0d3b28b26729fdbe2719e7b4186aaba.json`
(same origin commit, carried as `0041` in that repo's own series).
