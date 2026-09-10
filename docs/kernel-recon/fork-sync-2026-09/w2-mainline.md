# Wave 2 refutation — mainline / 6.18.49 / v7.2.3 claims (W2-mainline)

Written 2026-09-10. Independent re-derivation of every "present in / absent from mainline,
6.18.49, v7.2.3" statement Wave 1 made for records 9854075c8 (Q6), 41c45f378 (Q8), 7c75b1b46
(Q5), a14b5e8e1 (Q10), ea222122 (Q3), and the five `stable-drift-verdicts-B.md` explicit rows
(0027/0028/0030/0036/0047). Every command below was run in this session against
`$S=/tmp/claude-0/-home-user-Buildroot-MiSTer/0e3d989d-e15d-5ee0-9202-389bff28dbb8/scratchpad`;
nothing is copied from the records under review. Trees confirmed at start:
`$S/mainline` HEAD `50d05c7c76c9` (v7.3-rc2 area), `$S/linux` HEAD `1c732c6b94f0` ("Linux
6.18.49", tags `v6.18.39`/`v7.2.3` present), `$S/linux-7.2` HEAD `58e7295cfecadd` ("Linux
7.2.3").

## 1. Q6 exfat dir read-ahead (`9854075c8`) — **CONFIRMED**, all five sub-claims

**(a) mainline shape.**
```
$ grep -rn exfat_dir_readahead $S/mainline/fs/exfat/    -> (no output)
$ grep -rn exfat_blk_readahead $S/mainline/fs/exfat/
fatent.c:159:int exfat_blk_readahead(struct super_block *sb, sector_t sec,
fatent.c:202:  exfat_blk_readahead(sb, sec, &ra, &ra_cnt, end);
dir.c:663:      exfat_blk_readahead(sb, sec, &ra, &cnt, sec + ra_count - 1);
exfat_fs.h:522: int exfat_blk_readahead(...);
balloc.c:107:   exfat_blk_readahead(sb, sector + i, &ra, &ra_cnt, end);
$ grep -n "blk_start_plug\|blk_finish_plug" $S/mainline/fs/exfat/fatent.c
180:    blk_start_plug(&plug);
183:    blk_finish_plug(&plug);
```
Read `fatent.c:159-183` and `dir.c:640-665` directly: `exfat_blk_readahead()` (fatent.c) does
the plugging (`blk_start_plug`/`for sb_breadahead`/`blk_finish_plug`, lines 159-183); its sole
caller in `dir.c` is `exfat_get_dentry()` at `dir.c:663`
(`exfat_blk_readahead(sb, sec, &ra, &cnt, sec + ra_count - 1);`). `exfat_dir_readahead` does
not exist in mainline. Matches the record's quote verbatim, including the plug body.

**(b) v7.2.3 already has that shape; the fork's hunk FAILS there.**
```
$ git -C $S/linux show v7.2.3:fs/exfat/dir.c | grep -n "exfat_dir_readahead\|exfat_blk_readahead"
657:    exfat_blk_readahead(sb, sec, &ra, &cnt, sec + ra_count - 1);
$ git -C $S/linux show v7.2.3:fs/exfat/fatent.c | grep -n "exfat_blk_readahead\|blk_start_plug"
159:int exfat_blk_readahead(...)
180:    blk_start_plug(&plug);
183:    blk_finish_plug(&plug);
202:    exfat_blk_readahead(sb, sec, &ra, &ra_cnt, end);
```
`exfat_get_dentry()` starts at v7.2.3 `dir.c:630` (grepped: `struct exfat_dentry
*exfat_get_dentry(struct super_block *sb,` at line 630), the readahead call at 657 — matches
the record's "630-663"/"657" exactly. `diff` of v7.2.3's fatent.c:155-186 against mainline's
same range: **identical, exit 0**.

Reproduced the dry-run with the fork's *actual* 4-line hunk (`git -C $S/fork-6.18 show
9854075c86455942c2ce57e0b7dc80e3e2c5b108 -- fs/exfat/dir.c`, not a synthetic patch):
```
$ patch -p1 -F0 --dry-run -d apply-618 < q6.patch      (6.18.49 dir.c)
checking file fs/exfat/dir.c
Hunk #2 succeeded at 683 (offset 38 lines).

$ patch -p1 -F0 --dry-run -d apply-723 < q6.patch      (v7.2.3 dir.c)
checking file fs/exfat/dir.c
Hunk #1 FAILED at 6.
Hunk #2 FAILED at 644.
2 out of 2 hunks FAILED
```
The v7.2.3 failure output is byte-identical to what the record quotes ("Hunk #1 FAILED at 6.
Hunk #2 FAILED at 644. 2 out of 2 hunks FAILED"). Confirmed.

**(c) 6.18.49 dir.c has the unplugged loop.**
```
$ grep -n exfat_dir_readahead $S/linux/fs/exfat/dir.c
659:static int exfat_dir_readahead(struct super_block *sb, sector_t sec)
710:            exfat_dir_readahead(sb, sec);
```
Read lines 658-672: bare `for (i = 0; i < ra_count; i++) sb_breadahead(...)` loop, no plug.
Matches the record's quote exactly, including the function's start line (659).

**(d) only stable exfat commit in range, disjoint.**
```
$ git -C $S/linux log --oneline v6.18.39..HEAD -- fs/exfat/
62dde71ca exfat: preserve benign secondary entries during rename and move
```
Exactly one commit. `git -C $S/linux show 62dde71ca2c8 -- fs/exfat/dir.c` touches only
`@@ -481,31 +481,70 @@ static void exfat_free_benign_secondary_clusters` and
`@@ -513,7 +552,7 @@ void exfat_remove_entries` — nowhere near `exfat_dir_readahead` at
line 659. Confirmed disjoint.

**(e) balloc.c precedent.**
```
$ sed -n '73,119p' $S/linux/fs/exfat/balloc.c
```
`struct blk_plug plug;` at line 77; `if (max_ra_count && 0 == (i % max_ra_count)) {
blk_start_plug(&plug); for (j = i; ...) sb_breadahead(sb, sector + j); blk_finish_plug(&plug);
}` at lines 108-114, immediately before `sbi->vol_amap[i] = sb_bread(sb, sector + i);` at 116
— matches the record's quote. Mainline's `balloc.c:107` calls `exfat_blk_readahead()` directly
(no inline plug), confirming mainline generalized the same precedent one refactor further, as
the record states.

**Verdict: CONFIRMED**, no corrections.

## 2. Q8 Stadia-FF IDs (`41c45f378`) — **CONFIRMED**

```
$ grep -n "1460\|595a\|16d0\|1209" $S/mainline/drivers/hid/hid-google-stadiaff.c   -> exit 1
$ grep -n "1460\|595a\|16d0\|1209" $S/linux/drivers/hid/hid-google-stadiaff.c      -> exit 1
$ git -C $S/linux show v7.2.3:drivers/hid/hid-google-stadiaff.c | grep -n "1460\|595a\|16d0\|1209" -> exit 1
```
Absent from all three trees, confirmed by direct grep (not trusting the record's "exit 1"
claims).

No other hid driver claims either full VID:PID pair:
```
$ grep -n "0x16[dD]0\|0x1209\|0x1460\|0x595[aA]" $S/linux/drivers/hid/hid-ids.h
963:#define USB_VENDOR_ID_MCS  0x16d0        (unrelated vendor, no PID 0x1460 entry)
$ grep -rln "0x1460\|0x595[aA]" $S/linux/drivers/hid/*.c    -> (no output)
$ grep -n "0x1209" $S/linux/drivers/hid/hid-alps.c
18:#define HID_PRODUCT_ID_U1   0x1209        (different vendor's product id, not the pid.codes pair)
```

`-F0` dry-run of the fork's actual two-line hunk (`git -C $S/fork-6.18 show
41c45f378e8f433b56c4da9b80edcdfd67fcebfb -- drivers/hid/hid-google-stadiaff.c`) against both
trees, verbose:
```
$ patch -p1 -F0 --dry-run --verbose -d q8/618 < q8.patch | tail -3
Using Plan A...
Hunk #1 succeeded at 143.
done
$ patch -p1 -F0 --dry-run --verbose -d q8/723 < q8.patch | tail -3
Using Plan A...
Hunk #1 succeeded at 143.
done
```
Zero offset, zero fuzz, identical line (143) on both trees. Matches the record's claim
exactly.

**Verdict: CONFIRMED**, no corrections.

## 3. Q5 xpad `skip_8bitdo_init` (`7c75b1b46`) — **CORRECTED** (content confirmed, one line-number citation fixed)

```
$ grep -n skip_8bitdo $S/mainline/drivers/input/joystick/xpad.c    -> exit 1
$ grep -n skip_8bitdo $S/linux/drivers/input/joystick/xpad.c       -> exit 1
```
No `skip_8bitdo` anywhere in mainline or 6.18.49. Confirmed.

2dc8:3106 row text, 6.18.49 vs v7.2.3:
```
6.18.49:409:  { 0x2dc8, 0x3106, "8BitDo Ultimate Wireless / Pro 2 Wired Controller", 0, XTYPE_XBOX360 },
v7.2.3:375:   { 0x2dc8, 0x3106, "8BitDo Ultimate Wireless / Pro 2 Wired Controller", 0, XTYPE_XBOX360 },
```
Identical text, only the line number differs (line-count offset between the two trees).
Confirmed identical.

`xpad_start_input()`'s `XTYPE_XBOX360` block: extracted both trees' full function body and
diffed —
```
$ diff <(sed -n '1809,1844p' $S/linux/.../xpad.c) <(sed -n '1776,1811p' <v7.2.3 xpad.c>)
BYTE-IDENTICAL
```
Confirmed byte-identical, matching the record's substantive claim.

**Correction found**: the record's `upstream.vanilla_file_line` and `vanilla_quote` cited the
6.18.49 location as `xpad.c:2120-2140`. Grounding the actual file: `xpad_start_input()` starts
at **line 1809**, and `if (xpad->xtype == XTYPE_XBOX360) {` is at **line 1823**, block ends
line ~1843 — not 2120-2140 (off by ~300 lines; likely copy/paste from an earlier
line-numbering pass on a different file state). The v7.2.3 citation (`1790-1810`) was
independently confirmed *correct* (function at 1776, `XTYPE_XBOX360` guard at 1790). The
quoted C code itself was accurate and remains byte-identical to v7.2.3 — only the 6.18.49 line
numbers were wrong. Fixed in place in
`docs/kernel-recon/records/7c75b1b469e4dfd8bf59f9c28a25af16cddd2d9b.json`
(`upstream.vanilla_file_line`, `upstream.vanilla_quote`), and logged in that record's
`wave2_corrections` array. Disposition (`carried`) is unaffected.

**Verdict: CORRECTED** (citation only; substance CONFIRMED).

## 4. Q10 PR #92 hid-nintendo (`a14b5e8e1`) — **CONFIRMED**

```
$ grep -n "E4:17:D8\|8bitdo\|8BitDo" $S/mainline/drivers/hid/hid-nintendo.c   -> exit 1
```
No baudrate-skip logic in mainline. Confirmed the pre-patch ordering is still what mainline
ships:
```
$ grep -n "JC_USB_CMD_BAUDRATE_3M\|joycon_read_info(ctlr)" $S/mainline/drivers/hid/hid-nintendo.c
101:#define JC_USB_CMD_BAUDRATE_3M    0x03
2528:   ret = joycon_send_usb(ctlr, JC_USB_CMD_BAUDRATE_3M, HZ);
2554:   ret = joycon_read_info(ctlr);
```
Baudrate (2528) still precedes `read_info` (2554) in mainline — the unreordered, pre-fix
shape — consistent with "mainline has no skip".

Three stable hid-nintendo commits in range, re-listed independently:
```
$ git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/hid/hid-nintendo.c
5efcd7bbf HID: nintendo: stop device IO before hid_hw_stop on probe failure
268679f50 HID: nintendo: register input device after capabilities are set
51cfd1adb HID: nintendo: fix out-of-bounds read in joycon_ctlr_read_handler()
```
Hunk regions (own `git show`, `@@` lines): `5efcd7bbf` → `nintendo_hid_probe()` @@ -2692 / @@
-2722; `268679f50` → `joycon_input_create()` @@ -2138 / @@ -2181; `51cfd1adb` →
`joycon_ctlr_read_handler()` @@ -2559. `joycon_init()` (the baudrate/handshake function this
PR reorders) is at **line 2461** in 6.18.49
(`grep -n "^static int joycon_init" $S/linux/.../hid-nintendo.c` → `2461:static int
joycon_init`), with `JC_USB_CMD_BAUDRATE_3M` at 2471 and `joycon_read_info(ctlr)` at 2497 —
disjoint from all three stable hunk regions (2122-2181, 2557-2568, 2692-2728). None of the
three touch the baudrate/handshake path.

**Verdict: CONFIRMED**, no corrections.

## 5. `stable-drift-verdicts-B.md` explicit rows — **CONFIRMED**, all five

**0047** — `2c4e:0115` absence/presence:
```
$ grep -n 2c4e $S/linux/drivers/bluetooth/btusb.c
534:    { USB_DEVICE(0x2c4e, 0x0128), ...
$ git -C $S/linux show v7.2.3:drivers/bluetooth/btusb.c | grep -n 2c4e
535:    { USB_DEVICE(0x2c4e, 0x0128), ...
830:    { USB_DEVICE(0x2c4e, 0x0115), ...
```
`0x0115` absent at 6.18.49, present at v7.2.3. Exact match to the verdicts doc.

**0027** — mt76x2 Xbox adapter IDs:
```
$ grep -n "045e, 0x02e6\|045e, 0x02fe" $S/linux/drivers/net/wireless/mediatek/mt76/mt76x2/usb.c
26:     { USB_DEVICE(0x045e, 0x02e6) },        /* XBox One Wireless Adapter */
27:     { USB_DEVICE(0x045e, 0x02fe) },        /* XBox One Wireless Adapter */
```
Both IDs still present in 6.18.49, matching the two IDs `0027-*.patch`'s own hunk names
(`grep` of the patch file confirms it removes exactly `0x045e,0x02e6` / `0x045e,0x02fe`).
Confirmed.

**0036** — `btusb_setup_csr` lmp_subver checks unchanged in range: the three stable btusb.c
commits in range (`dc0c462fa8` quirks_table row, `f14d41dbc2` `btusb_setup_qca`/`qca_get_fw_*`,
`8881daaafa` `btusb_setup_realtek`) touch `@@ -802`, `@@ -3345.. -3625`, `@@ -2716` respectively
— `btusb_setup_csr()` (6.18.49, lines 2443-2525, `lmp_subver` checks at 2473-2525) is not
touched by any of them. Confirmed unchanged.

**0030** — i2c-designware dev_err line:
```
$ git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/i2c/busses/i2c-designware-master.c
(no output)
$ sed -n '855,858p' $S/linux/drivers/i2c/busses/i2c-designware-master.c
        ret = i2c_dw_wait_transfer(dev);
        if (ret) {
                dev_err(dev->dev, "controller timed out\n");
```
Zero commits in range; line still `dev_err`. Confirmed unchanged.

**0028** — dwc2:
```
$ git -C $S/linux log --oneline v6.18.39..HEAD -- drivers/usb/dwc2/
(no output — 0 commits)
```
Confirmed zero stable commits under `drivers/usb/dwc2/` in the range.

**Verdict: CONFIRMED**, all five, no corrections.

## 6. Q3 fbdev (`ea222122`) — mainline commit 8813e86f6d82 — **CONFIRMED as stated (unverifiable + partial verification correctly scoped)**

```
$ git -C $S/mainline cat-file -e 8813e86f6d82
fatal: Not a valid object name 8813e86f6d82
```
Confirmed: this SHA is genuinely unreachable from the depth-1 `$S/mainline` clone, exactly as
the record states (it never lists it in `upstream.vanilla_shas`, consistent with the
grounding contract).

What **can** be verified — the `fb_mmap()` WARN path — is present and matches the record's
quote:
```
$ sed -n '314,328p' $S/linux/drivers/video/fbdev/core/fb_chrdev.c
static int fb_mmap(struct file *file, struct vm_area_struct *vma)
{
        struct fb_info *info = file_fb_info(file);
        int res;

        if (!info)
                return -ENODEV;

        if (fb_WARN_ON_ONCE(info, !info->fbops->fb_mmap))
                return -ENODEV;

        mutex_lock(&info->mm_lock);
        res = info->fbops->fb_mmap(info, vma);
        mutex_unlock(&info->mm_lock);

        return res;
}
```
Same `fb_WARN_ON_ONCE(info, !info->fbops->fb_mmap)` guard also present verbatim in
`$S/mainline/drivers/video/fbdev/core/fb_chrdev.c:316`, confirming this is still the shape
current mainline ships (i.e. `8813e86f6d82`'s effect — no per-driver-default `fb_mmap` — is
still in force upstream; a explicit `fb_ops.fb_mmap` really is required, which is what both
`0001` and the fork's `ea222122` supply).

**Verdict: CONFIRMED** — the record correctly declines to assert the unreachable SHA and
correctly grounds what it can see instead; independently re-confirmed both halves. No
corrections.

## Summary of dispositions

| Claim group | Record | Result |
|---|---|---|
| Q6 exfat (a)-(e) | `9854075c86455942c2ce57e0b7dc80e3e2c5b108` | CONFIRMED |
| Q8 Stadia IDs | `41c45f378e8f433b56c4da9b80edcdfd67fcebfb` | CONFIRMED |
| Q5 xpad | `7c75b1b469e4dfd8bf59f9c28a25af16cddd2d9b` | CORRECTED (line-number citation only; substance confirmed) |
| Q10 PR #92 hid-nintendo | `a14b5e8e1c9c23f71b5d4cc300a7dab3083e546f` | CONFIRMED |
| Drift-verdicts-B (0027/0028/0030/0036/0047) | `stable-drift-verdicts-B.md` | CONFIRMED, all five |
| Q3 fb_mmap / 8813e86f6d82 | `ea2212221ad137cf26bf5caa7ad3dab7216435a6` | CONFIRMED |

No claim was REFUTED. One CORRECTED item (Q5, wrong 6.18.49 line-number citation in
`upstream.vanilla_file_line`/`upstream.vanilla_quote`), fixed in place with a
`wave2_corrections` entry; the record's disposition (`carried`) was not touched.
