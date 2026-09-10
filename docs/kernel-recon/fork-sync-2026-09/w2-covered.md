# W2-covered — refutation pass on "already covered" claims (Q1, Q2, Q3, Q7)

Wave 2 refutation agent, fork-sync-2026-09. Target: the four "already covered by our
config / our patch" records named in the assignment. Grounding: env.md (v6.18.49, release
commit `1c732c6b94f0faee1526bd375add2fe10cba2e26`, on the gregkh mirror; v6.18.50 itself
unreachable). Trees used: `$S/linux`, `$S/fork-6.18`, `$S/main` (Main_MiSTer HEAD
`6cda9cc546c4`, 2026-09-10, depth 120).

Note on method: while working this task, a second concurrent Wave-2 agent
(`W2-coupling`) was independently correcting two of the same defects in the same record
files. Where its `wave2_corrections` entries already matched what my own independent
re-derivation found (same file:line, same evidence), I report it as CONFIRMED-by-two-passes
below rather than re-doing the edit; I only edited what was still wrong when I got to it.

---

## Q1 — `aec7dc3aa4846385736f1d54c9155e3b3c726708` (CONFIG_TUN, MiSTer-v6.18)

**Suspected defect 1 — `coupled=true` with `main_mister_ref=null`.**
REFUTED-the-refutation: `coupled=true` is *correct*, and strongly so. Independent grep of
`$S/main` for `/dev/net/tun`, `TUNSETIFF`, `IFF_TAP` found real, first-party hits:
`support/minimig/minimig_a2065_ethernet.cpp:41` (`open("/dev/net/tun", O_RDWR|O_CLOEXEC)`),
`:46` (`ifr.ifr_flags = IFF_TAP | IFF_NO_PI;`), `:48` (`ioctl(fd, TUNSETIFF, &ifr)`), and
`support/minimig/minimig_a2065.cpp:120` (second `open("/dev/net/tun", O_RDWR)` in the
A2065_TAP capability probe). `git -C $S/main log -S"TUNSETIFF" -- support/minimig/minimig_a2065_ethernet.cpp`
shows this landed in commit `df0538a` ("minimig: add A2065 Ethernet card support (#1247)"),
2026-07-25/26 — **one day after** both the fork commit (2026-07-24) and the sibling
`5fcfae369` record's own (correct-at-the-time) zero-hit grep. The sibling record was right
when it was written; it is now stale, and so was this Wave-1 record's `main_mister_ref:
null`, for the same reason. A concurrent `W2-coupling` pass had already fixed
`userspace_coupling.main_mister_ref` in this file with the identical citations before I
reached it — CONFIRMED (two independent passes, same evidence). **CORRECTED** (already, not
by me).

**Suspected defect 2 — `configs/mister_de10nano_defconfig:133` citation.**
CONFIRMED stale. `find /home/user/Buildroot_MiSTer -iname '*mister_de10nano_defconfig*'`
returns nothing — the file is gone post-2026-09 fragment split. The
`BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` pin now lives at
`configs/fragments/de10nano.fragment:33`. **CORRECTED** (by me, this pass) —
`dependencies.superseded_by[0]` rewritten, `wave2_corrections` entry appended.

Disposition (`dropped-deliberate`) is unaffected by either correction — both are citation
fixes, not a change to what actually happened.

---

## Q2 — `33a0521fd46b3991ec3a882f659bceb2c1cb4399` (CONFIG_RTW88_8821AU, MiSTer-v6.18)

Re-resolved independently: copied `board/mister/de10nano/linux.config` to a scratch
`.config`, ran `make -C $S/linux O=<tmp> ARCH=arm LLVM=1 olddefconfig`. Result:
```
CONFIG_RTW88_8821AU=m
CONFIG_RTW88_8821A=m
CONFIG_RTW88_88XXA=m
CONFIG_RTW88_USB=m
```
— **CONFIRMED**, exact match to the record's claim.

Device IDs: `$S/linux/drivers/net/wireless/realtek/rtw88/rtw8821au.c:48-53` —
`USB_DEVICE_AND_INTERFACE_INFO(0x2357, 0x011e, ...)` / `0x011f` / `0x0120`, each `/* TP Link */`
— **CONFIRMED**, all three IDs present, not just `011e`.

Firmware: `configs/fragments/image-common.fragment:43` sets
`BR2_PACKAGE_LINUX_FIRMWARE_RTL_RTW88=y`; `docs/wifi-parity.md:420-423` maps
`CONFIG_RTW88_8821AU` → `rtw88/rtw8821a_fw.bin` via that same symbol — **CONFIRMED**. Also
checked that `image-common` is actually in the full-image build:
`configs/fragments/stacks.mk:24` — `DE10NANO_FRAGMENTS := common de10nano image-common
de10nano-image` — so the firmware genuinely reaches the shipped image, not just the
kernel-only stack (which deliberately excludes `image-common`, per
`docs/buildroot-config.md:3071`).

`userspace_coupling.coupled=false`: independently re-verified, `grep -rniE
'8821au|rtw8821|0x2357|2357:' $S/main` — zero hits — **CONFIRMED**.

**Looking for a way the dongle still would not work — none found.** Module ships (`=m`,
full-image stack, not kernel-only), firmware ships (`image-common`), `RTW88_USB=m` present,
VID:PIDs present in the driver. The one candidate risk I could not resolve either way: three
docs (`fork-sync-2026-07.md:88-89`, `de25-kernel-config.md:222`, `PLAN.md:218`) assert as
settled project policy that "the module directory name does not match `uname -r` on
MiSTer, so module autoload is unreliable" — but every one of those three citations is
restating the same unsourced claim (used to justify `=y` for TUN/MACVLAN/cpufreq), not
independently grounding it, and none of them says whether it also applies to `=m` WiFi
modules loaded via eudev's hotplug/coldplug (`70-persistent-net.rules`,
`board/mister/common/linux-mister.fragment:175` `UEVENT_HELPER=/sbin/hotplug`). I could not
find or rule out a real `uname -r`/module-directory mismatch from the trees available in
this session (no live target to check `uname -r` against `/lib/modules/`). **Flagged as
needs-verification, not a confirmed defect** — left for the orchestrator; disposition
(`dropped-deliberate`) unchanged.

---

## Q3 — `ea2212221ad137cf26bf5caa7ad3dab7216435a6` (fbdev fb_ops, MiSTer-v6.18)

`arch/arm/lib/memcpy.S` — content quote CONFIRMED verbatim; line range was off by one
(`57-65` vs actual `56-66`, the quoted block runs from the `/* Prototype... */` comment at
line 56 through `ENDPROC(__memcpy)` at line 66). **CORRECTED** (by me, this pass) — fixed
in `upstream.vanilla_quote`; left as-is in the free-text `recommendation`/`notes` fields
(same content, lower-value to hand-patch every prose occurrence).

`arch/arm/include/asm/io.h:320-326` `memcpy_fromio`/`memcpy_toio` (the `#ifndef __ARMBE__`
inline-`mmiocpy` branch) — **CONFIRMED** exact, and confirmed that branch is the one our
target actually takes (little-endian ARM, no `__ARMBE__`).

`fb_io_fops.c` / `fb_sys_fops.c` — read in full.
Partial REFUTATION of the "differ only in the copy primitive" framing: the two read paths
also differ in **buffering strategy**, which the record's equivalence analysis does not
mention. `fb_io_read`/`fb_io_write` allocate a `kmalloc`'d bounce buffer capped at
`PAGE_SIZE` and copy in a chunked loop (`fb_io_fops.c:36-72`); `fb_sys_read`/`fb_sys_write`
do **one** direct `copy_to_user`/`copy_from_user` against `screen_buffer` for the whole
count, no bounce buffer, no chunking, no allocation (`fb_sys_fops.c:47-59`). I chased
whether that is a real behavioural difference: `arch/arm/lib/copy_to_user.S` and
`copy_from_user.S` both `#include "copy_template.S"` — the same block-copy primitive
`memcpy`/`mmiocpy` use — so the instruction-level access pattern is identical either way,
and both paths compute the same short-read-on-fault semantics (`ret = count - trailing`).
So: **CONFIRMED** the record's bottom-line conclusion (behaviourally identical on this
target), but the "only the copy primitive differs" sentence is an overstatement — the
buffering shape differs too. Worth a note if 0001 is ever actually switched to
`__FB_DEFAULT_SYSMEM_OPS_RDWR`, since `fb_sys_read`/`write` also gate on `!(info->flags &
FBINFO_VIRTFB)` for a one-time `fb_warn_once` (`fb_sys_fops.c:27-28`) that `fb_io_read`
doesn't have the mirror image of — MiSTer_fb sets no `FBINFO_VIRTFB` flag today, so this
would print a new one-time dmesg line, cosmetic only.

Kconfig `FB_SYSMEM_FOPS`/`FB_IOMEM_FOPS` at `Kconfig:124-126,146-148`, `Makefile:31,35`,
`__FB_DEFAULT_IOMEM_OPS_MMAP` expanding to `.fb_mmap = fb_io_mmap` at `fb.h:566-567` — all
**CONFIRMED** exact line-for-line.

`kernel/iomem.c:48-50,69,110-111` memremap doc + `MEMREMAP_WT` path, `include/linux/io.h:158`
prototype — **CONFIRMED** exact.

Main_MiSTer `/dev/fb0` usage: `video.cpp:3773` open, `:3776`/`:3784`
`ioctl(fb,FBIO_WAITFORVSYNC,&zero)` — CONFIRMED. The `close(fb)` citation
(`video.cpp:3789`) was **wrong** — line 3789 is `vs_wait()`'s closing brace, not a
`close()` call; the actual calls are at `:3779` (error branch, uncited) and `:3786`
(success branch, the one meant). Already **CORRECTED** by the concurrent `W2-coupling`
pass to `:3786`, matching my independent finding exactly. I additionally chased the one
loose end the record's grep could have missed: `video.cpp:2417` contains the string
`"Unable to mmap FB!\n"`. Traced it — it is `fb_init()`'s `shmem_map()` call
(`shmem.cpp:18-35`), which `open()`s **`/dev/mem`**, not `/dev/fb0`, and does its own
`mmap()` there for the FPGA frame-reader window — a completely different kernel path
(`drivers/char/mem.c`'s `mem_fops`, not `MiSTer_fb.c`'s `fb_ops`). So the record's "no
mmap(2) call on this fd" claim survives — **CONFIRMED**, false alarm on my part, traced and
ruled out.

---

## Q7 — `e6f377e7d178c20a4c28b09e1f70c4b8d4cbffe2` ("Update defconfig.", Sorgelig)

**The assignment's own premise is wrong, not the record.** `git -C $S/fork-6.18 show
e6f377e7d178c20a4c28b09e1f70c4b8d4cbffe2` shows exactly three added lines:
```
+CONFIG_RTW88_8821A=m
+CONFIG_FB_SYSMEM_FOPS=y
+CONFIG_FB_IOMEM_FOPS=y
```
No `ARM_SOCFPGA_CPUFREQ` symbol appears anywhere in this commit, and the record makes no
such claim — its `notes` field quotes the same three lines verbatim, correctly attributed
to Q2 (`33a0521fd4`, RTW88_8821AU) and Q3 (`ea2212221a`, fb ops) as the auto-selecting
parents. `ARM_SOCFPGA_CPUFREQ`/`59bcae8eb` is a different item entirely — the cpufreq port,
tracked as Q4 in `PLAN.md §2.4` ("decision required; Opus"), untouched by this commit. This
is a mismatch between the attack brief and the actual commit content, not a defect in the
record. **CONFIRMED** — record is accurate; REFUTED the premise that it attributes
`ARM_SOCFPGA_CPUFREQ` anywhere.

Per-symbol claims cross-checked against my own Q2/Q3 re-derivations above (auto-select of
`RTW88_8821A=m` from `RTW88_8821AU=m`, and `FB_SYSMEM_FOPS=y`/`FB_IOMEM_FOPS=y` from
`FB_MISTER`'s two `select`s) — **CONFIRMED** on all three lines.

---

## Summary of edits made to record files this pass

- `aec7dc3aa...json`: `dependencies.superseded_by[0]` path corrected
  (`configs/mister_de10nano_defconfig:133` → `configs/fragments/de10nano.fragment:33`);
  `wave2_corrections` entry appended. (The `main_mister_ref` fix was already applied by a
  concurrent agent before I got to it — verified correct, not re-edited.)
- `ea2212221a...json`: `upstream.vanilla_quote`'s `memcpy.S` citation corrected (`57-65` →
  `56-66`); `wave2_corrections` entry appended. (The `close(fb)` line-number fix was
  likewise already applied by a concurrent agent — verified correct, not re-edited.)
- `33a0521fd4...json`, `e6f377e7d...json`: no edits — no defect found.

No disposition was changed on any record.
