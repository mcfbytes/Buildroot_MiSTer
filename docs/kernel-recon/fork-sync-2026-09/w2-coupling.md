# Wave 2 — userspace-coupling refutation (W2-coupling)

Re-derived every `userspace_coupling` block and every Main_MiSTer `path:line` citation in the
eight Wave 1 records below against `$S/main` (MiSTer-devel/Main_MiSTer, HEAD `6cda9cc546c4b32e256a19931128b82586253812`,
2026-09-10, depth 120 — per `fork-sync-2026-09/env.md`). All greps and line reads were run
directly against that checkout; no line number below was copied from a Wave 1 record without
re-reading the file.

Two FALSE/MISSING citations were found and corrected in place (JSON `wave2_corrections`
arrays). No `coupled` flag needed to flip — but one flag (Q1/TUN) required correcting because
this wave's own assumed test criterion turned out to be contradicted by the live tree; see
the Q1 row below and the "assumption contradicted" note.

## Per-record citation tables

### aec7dc3aa4846385736f1d54c9155e3b3c726708 — Q1, CONFIG_TUN

| citation | verdict | evidence |
|---|---|---|
| `userspace_coupling.main_mister_ref` = `null` (with `coupled: true`) | **MISSING → corrected** | A `coupled=true` record must cite `path:line` (worker-instructions.md pilot-lesson + escalation rule); none was present. `grep -rniE '/dev/net/tun|TUNSETIFF|IFF_TAP|IFF_TUN|if_tun\.h' $S/main` is **non-zero** (4 hits, all in `support/minimig/minimig_a2065_ethernet.cpp` and `minimig_a2065.cpp`), so a citation exists and was added: `minimig_a2065_ethernet.cpp:24,41,46,48` and `minimig_a2065.cpp:120`. |

**This wave's supplied test criterion for Q1 ("grep expected zero, so coupled should be
false; the tap use case is community scripts") is itself CONTRADICTED by the live tree.**
`support/minimig/minimig_a2065_ethernet.cpp` (`open("/dev/net/tun",...)`, `IFF_TAP`,
`TUNSETIFF`) and `minimig_a2065.cpp` (`A2065_TAP` capability probe) are first-party
Main_MiSTer code, built into the shipped binary via the Makefile's
`CPP_SRC += $(wildcard ./support/*/*.cpp)` rule — not a community script. `git -C $S/main log`
shows this code landed 2026-07-26 (`df0538ab4d9a`, "minimig: add A2065 Ethernet card support
(#1247)"), two days *after* the fork's 2026-07-24 TUN-enablement commit — i.e. Main_MiSTer grew
a direct consumer of `/dev/net/tun`+`IFF_TAP` almost immediately. The Wave-1 record's
`coupled: true` was therefore already the evidence-backed value (its own `impact.effect_if_absent`
prose independently describes the same A2065/tap scenario); only the missing citation needed
fixing. **Correction applied**, `coupled` left unchanged (`true`).

### 33a0521fd46b3991ec3a882f659bceb2c1cb4399 — Q2, CONFIG_RTW88_8821AU

| citation | verdict | evidence |
|---|---|---|
| `userspace_coupling` = `{coupled:false, main_mister_ref:null}`, notes claim "grep ... for '8821AU','8821au','rtw8821','2357' yields no matches" | **CONFIRMED** | `grep -rniE '8821AU\|8821au\|rtw8821\|2357' $S/main` → zero hits. `coupled=false` is correct, matches the Q2-expected-false test. |

### ea2212221ad137cf26bf5caa7ad3dab7216435a6 — Q3, fbdev fb_ops

| citation | verdict | evidence |
|---|---|---|
| `video.cpp:3773` — `open("/dev/fb0", O_RDWR\|O_CLOEXEC)` | CONFIRMED | `sed -n '3771,3790p' $S/main/video.cpp`: line 3773 is exactly `int fb = open("/dev/fb0", O_RDWR \| O_CLOEXEC);`. |
| `video.cpp:3776` — `ioctl(fb, FBIO_WAITFORVSYNC, &zero)` (first call, inside the `if`) | CONFIRMED | line 3776 is `if (ioctl(fb, FBIO_WAITFORVSYNC, &zero) == -1)`. |
| `video.cpp:3784` — `ioctl(fb, FBIO_WAITFORVSYNC, &zero)` (second call) | CONFIRMED | line 3784 is exactly that statement. |
| `video.cpp:3789` — `close(fb)` | **FALSE CITATION → corrected to 3786** | Line 3789 is the function's closing brace `}`, not a `close()` call. The actual (second/normal-path) `close(fb)` is at **line 3786**; there is also an earlier `close(fb)` at line 3779 in the error branch, uncited either way. Content claim (no read/write/mmap on the fd) is still correct — only the line number was wrong. |
| `video.cpp:3465` and `video.cpp:4307` — `/sys/module/MiSTer_fb/parameters/mode` sysfs writes | CONFIRMED | `grep -n '/sys/module/MiSTer_fb/parameters/mode' video.cpp` → exactly lines 3465 and 4307. |
| (unfixed, out of correction scope) `recommendation` field's own prose: "main/video.cpp:3773-3789 opens the fd only for ioctl(...)" | CONFIRMED as a range | 3773–3789 correctly bounds the whole `vs_wait()` function (3771–3789); it is a span reference, not a specific-line claim, so it is not a false citation. |
| Repo-wide grep for `fb_mmap`/`FBIOGET`/`mmap(` near "fb" in `$S/main` | CONFIRMED empty | independently re-run: zero hits. Supports `coupled=false`. |

`coupled=false` verdict CONFIRMED: Main_MiSTer opens `/dev/fb0` only for
`ioctl(FBIO_WAITFORVSYNC)`; no `read(2)`/`write(2)`/`mmap(2)` call exists on that fd anywhere
in the tree.

### e6f377e7d178c20a4c28b09e1f70c4b8d4cbffe2 — Q7, "Update defconfig."

| citation | verdict | evidence |
|---|---|---|
| `userspace_coupling` = `{coupled:false, main_mister_ref:null}` | CONFIRMED | Pure defconfig-explicitness commit (auto-selected symbols made explicit); no Main_MiSTer citation asserted, none needed. Matches Q7-expected-false. |

### 41c45f378e8f433b56c4da9b80edcdfd67fcebfb — Q8, hid-google-stadiaff Classic2USB/RetroZord

| citation | verdict | evidence |
|---|---|---|
| `input.cpp:52-53` — `(vid == 0x16D0 && (pid == 0x127E \|\| pid == 0x1460)) // Reflex Adapt \|\| (vid == 0x1209 && pid == 0x595A); // RetroZord` | CONFIRMED | `sed -n '48,56p' input.cpp`: lines 52-53 match verbatim (inside `gcdb_use_usb_bcd_device()`). |
| `input.cpp:4176` — `make_unique(0x16D0, 0x1460, 1);  // Reflex Adapt Classic2USB` | CONFIRMED | line 4176 matches verbatim. |
| `input.cpp:4177` — `make_unique(0x1209, 0x595A, 1);  // RetroZord adapter` | CONFIRMED | line 4177 matches verbatim. |
| `input.cpp:5102` — `vid==0x1209 && pid==0x595A` with `strstr(input[i].name, "RZordPsWheel")` | CONFIRMED | line 5102 is `else if (((input[i].vid == 0x2341 \|\| (input[i].vid == 0x1209 && input[i].pid == 0x595A)) && strstr(input[i].name, "RZordPsWheel")) \|\|` — exact match. |
| `input.cpp:5349` — same VID:PID with `strstr(uniq, "RZordPsGun")` | CONFIRMED | line 5349 matches verbatim (the comment "//Namco Guncon..." is the preceding line, 5348). |
| `input.cpp:5496` — re-check of `0x16D0/0x1460` and `0x1209/0x595A` alongside `strlen(uniq)` | CONFIRMED | line 5496 matches verbatim. |

All six Q8 citations CONFIRMED byte-for-byte. `coupled=true` verdict CONFIRMED — matches the
Q8-expected-true test.

### 7c75b1b469e4dfd8bf59f9c28a25af16cddd2d9b — Q5, xpad skip_8bitdo_init (2dc8:3106)

| citation | verdict | evidence |
|---|---|---|
| `input.cpp:5852` and `input.cpp:6130-6131` cited as the *only* grep hits for `'2dc8'`, `'8BitDo'/'8bitdo'`, `'0x3106'`, `'skip_8bitdo'`, with the quoted text `// Menu button on 8BitDo Receiver in D-Input mode` / `if (ev.code == 9 && input[dev].vid == 0x2dc8 && (input[dev].pid == 0x3100 \|\| input[dev].pid == 0x3104))` attributed to 6130-6131 | CONFIRMED | `grep -n '2dc8' input.cpp` → only line 6131. `grep -rn '0x3106\|skip_8bitdo' $S/main` → zero hits anywhere. Lines 6130-6131 match the quoted text verbatim (comment at 6130, condition at 6131). Line 5852 is a legitimate separate grep hit for the string "8BitDo" (`//Menu combo on 8BitDo receiver in PSC mode`, vid 0x054c/pid 0x0cda) — listed, not misquoted, as it carries no quoted text of its own in this record. |

`coupled=false` verdict CONFIRMED: PID `0x3106` (the XTYPE_XBOX360 device this commit targets)
is referenced nowhere in Main_MiSTer; only the unrelated D-Input-mode PIDs `0x3100`/`0x3104`
are. Matches Q5-expected-false.

### 9854075c86455942c2ce57e0b7dc80e3e2c5b108 — Q6, exfat dir read-ahead plug

| citation | verdict | evidence |
|---|---|---|
| `userspace_coupling` = `{coupled:false, main_mister_ref:null}` | CONFIRMED | `grep -rniE 'exfat' $S/main` → zero hits anywhere in Main_MiSTer. Pure block-layer I/O-scheduling change with no userspace-visible interface; `coupled=false` correct, matches the Q6-expected-false grouping. |

### a14b5e8e1c9c23f71b5d4cc300a7dab3083e546f — Q10, hid-nintendo 8BitDo adapter (057e:2009)

| citation | verdict | evidence |
|---|---|---|
| `input.cpp:2752` — `else if (input[dev].vid == 0x057e && ((input[dev].pid & 0xFF00) == 0x2000))` | CONFIRMED | `sed -n '2745,2755p' input.cpp`: line 2752 matches verbatim. |
| `input.cpp:4733-4734` — `strcpy(input[l].idstr, "057e_2009"); strcpy(input[r].idstr, "057e_2009");` | CONFIRMED | `sed -n '4725,4738p' input.cpp`: lines 4733/4734 match verbatim. |
| `input.cpp:5309` — `else if (!strcasestr(input[n].name, "Pro Controller"))` | CONFIRMED | `sed -n '5303,5312p' input.cpp`: line 5309 matches verbatim. |
| `input.cpp:5852` — "Menu combo on 8BitDo receiver in PSC mode", vid 0x054c/pid 0x0cda | CONFIRMED | matches verbatim (same line independently re-verified for the Q5 record above). |
| `input.cpp:6130` — "Menu button on 8BitDo Receiver in D-Input mode", vid 0x2dc8/pid 0x3100\|0x3104 | CONFIRMED | comment at 6130, condition at 6131 (same lines independently re-verified for the Q5 record above). |

All five Q10 citations CONFIRMED. `coupled=true` verdict CONFIRMED — matches the
Q10-expected-true test: without hid-nintendo binding the 057e:2009 adapter, none of these
`input.cpp` code paths (LED mapping, joycon combining, WIIMOTE-quirk exclusion) ever execute
for this hardware.

## Coupled-flag verdict summary

| record | item | task's expectation | Wave-1 `coupled` | verdict |
|---|---|---|---|---|
| aec7dc3aa | Q1 CONFIG_TUN | expected false (per task brief) | `true` | **task's expectation itself refuted** — `true` is evidence-backed (Main_MiSTer's own A2065 tap-mode code, not a community script); citation added, flag unchanged |
| 33a0521fd | Q2 RTW88_8821AU | expected false | `false` | CONFIRMED |
| ea2212221a | Q3 fbdev fb_ops | verify, no true/false stated | `false` | CONFIRMED (one citation line-number fixed) |
| e6f377e7d | Q7 defconfig | expected false | `false` | CONFIRMED |
| 41c45f378 | Q8 stadiaff | expected true | `true` | CONFIRMED |
| 7c75b1b46 | Q5 xpad 2dc8 | expected false | `false` | CONFIRMED |
| 9854075c8 | Q6 exfat | expected false | `false` | CONFIRMED |
| a14b5e8e1 | Q10 057e:2009 | expected true | `true` | CONFIRMED |

Seven of eight records' `coupled` flags matched their expected test outcome on direct
re-derivation, with all cited Main_MiSTer lines confirmed accurate except two (see corrections
below). The eighth (Q1/TUN) had the *correct* flag already, but the task brief's own assumed
test criterion for it does not hold against the live `$S/main` tree — flagged loudly per the
grounding contract ("if the source disagrees, say so loudly").

## Corrections applied (JSON `wave2_corrections`)

| record | field | was | now |
|---|---|---|---|
| `aec7dc3aa4846385736f1d54c9155e3b3c726708.json` | `userspace_coupling.main_mister_ref` | `null` | `support/minimig/minimig_a2065_ethernet.cpp:24,41,46,48; support/minimig/minimig_a2065.cpp:120` |
| `ea2212221ad137cf26bf5caa7ad3dab7216435a6.json` | `userspace_coupling.main_mister_ref` (the `close(fb)` citation) | `main/video.cpp:3789 (close(fb))` | `main/video.cpp:3786 (close(fb))` |

No `disposition` field was touched on any record. No files other than these two JSON records
and this report were modified.

## Q4 memo facts (cpufreq / OCRAM — for the Q4 agent; no Q4 record created here)

**cpufreq / `scaling_*` / `system/cpu`:**
`grep -rniE 'cpufreq|scaling_(min|max|cur|governor|available)|system/cpu' $S/main` returns
**only** unrelated hits in `support/sharpmz/sharpmz.{h,cpp}` — a Sharp MZ-series emulated-core
debug clock-speed enum/string table named `SHARPMZ_DEBUG_CPUFREQ[]` (`"Normal","1MHz","100KHz",...`)
and its accessor functions (`sharpmz_get_next_debug_cpufreq()` etc.). This is FPGA-core debug
UI text, not a Linux `cpufreq`/`scaling_governor` sysfs interaction. **Zero genuine cpufreq
coupling found anywhere in Main_MiSTer** — no `/sys/devices/system/cpu/cpu*/cpufreq/*` path,
no `scaling_governor`/`scaling_min_freq`/`scaling_max_freq`/`scaling_cur_freq`/
`scaling_available_*` string, no `/sys/devices/system/cpu` path of any kind.

**OCRAM / `0xffff*` / "sram" / "flags":**
`grep -rniE '0xFFFF[0-9A-Fa-f]{3}|\bsram\b|OCRAM' $S/main` — real, on-topic hits (excluding the
many unrelated `0xFFFFFFFF`-as-sentinel/mask idioms scattered through `ide.cpp`, `input.cpp`,
`cfg.cpp`, the zstd/miniz/lzma/libchdr vendored libs, etc.):
- `fpga_base_addr_ac5.h:44` — `#define SOCFPGA_OCRAM_ADDRESS 0xffff0000` (Cyclone V HPS on-chip
  RAM physical base address).
- `fpga_system_manager.h:73` — `uint32_t eccgrp_ocram;` (System Manager ECC register struct
  field); `fpga_system_manager.h:113-115` — `#define SYSMGR_ECC_OCRAM_EN (1 << 0)`,
  `SYSMGR_ECC_OCRAM_SERR (1 << 3)`, `SYSMGR_ECC_OCRAM_DERR (1 << 4)` (OCRAM ECC enable/
  single-error/double-error status *flags*).
- `fpga_nic301.h:32,122,124,126` — `uint32_t ocram;`, `ocram_fn_mod_bm_iss;`,
  `ocram_wr_tidemark; /* 0x27040 */`, `ocram_fn_mod;` (NIC-301 interconnect register-map fields
  gating OCRAM bus-master access).
- No hits for the bare word "sram" outside of `support/n64/n64.cpp` (`"256K SRAM"`,
  `"768K SRAM"` — cartridge save-RAM size strings, unrelated to on-chip OCRAM) and one PSCII
  comment in `n64.cpp:1414`.

These are direct C struct/register definitions for the Cyclone V HPS's on-chip RAM and its
ECC/NIC-301 access-control registers (`/dev/mem`-style raw hardware access via the FPGA base
address headers), not Linux-kernel `mm`/`sram` driver or DTS coupling — worth flagging to the
Q4 agent as the concrete Main_MiSTer-side OCRAM touchpoints if Q4's item concerns an
OCRAM-address or ECC-flag kernel change.
