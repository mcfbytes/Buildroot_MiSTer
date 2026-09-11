# Candidate 1 — NSO Genesis/Mega Drive Bluetooth PID normalization

**No patch produced. The fix is already present on `MiSTer-v6.18` at `c129b0fac`.**

## What the assignment asked to check

The Wave 5 brief and `tree-diff-2026-09.md` §6 both list this as a Wave 5 candidate,
citing our carried `0038-hid-nintendo-nso-genesis-bt-pid.patch` (origin
`b00a72159aeb6996e1006d28383fdb8e2667746b`, Shig, "Add support for NSO Mega Drive
Controller (#50)") and instructing: *"check first whether his hid-nintendo.c already
normalizes hdev->product (tree-diff says no; verify with grep) and describe exactly
what differs."*

## What grep actually found

```
$ grep -n "hdev->product = " drivers/hid/hid-nintendo.c   # at c129b0fac
2177:		hdev->product = USB_DEVICE_ID_NINTENDO_GENCON;
```

Full context, `joycon_input_create()`, `drivers/hid/hid-nintendo.c:2162-2178` at
`c129b0fac34ad5d613bbec3f59d6036775e41c83`:

```c
	/*
	 * MiSTer: NSO Genesis/Mega Drive controller has the wrong PID via
	 * Bluetooth (reports 0x2017, the same PID as the NSO SNES
	 * controller -- see the comment on this in joycon_request_
	 * calibration()), so hdev->product (and therefore the input_dev
	 * id.product userspace GUID lookups key off, e.g. Main_MiSTer's
	 * SDL-format gamecontrollerdb.txt) is forced to the correct
	 * GENCON PID here based on the real ctlr_type read from the
	 * controller itself. Kernel-side button/axis mapping is already
	 * unaffected either way since it dispatches off ctlr->ctlr_type,
	 * never off hdev->product.
	 */
	if (hdev->product == USB_DEVICE_ID_NINTENDO_SNESCON &&
	    ctlr->ctlr_type == JOYCON_CTLR_TYPE_GEN)
		hdev->product = USB_DEVICE_ID_NINTENDO_GENCON;
```

This is the **same logic, same names, same placement** (immediately before
`devm_input_allocate_device()` in `joycon_input_create()`) as our own `0038`. The
`git diff` between our patched tree (`0001`-`0042` applied to pristine 6.18.38) and his
tree at `c129b0fac`, run for `tree-diff-2026-09.md`, shows **zero difference** at this
specific hunk — confirmed by re-diffing the two trees' `hid-nintendo.c` directly in this
session; the only differences in the surrounding file are unrelated (Famicom
`JOYCON_CTLR_TYPE_FAMIL`/`FAMIR` enum naming, comment wording on the NSO N64/Genesis
mapping tables covered by candidate 2, an `E4:17:D8` 8BitDo helper). His own comment
("MiSTer: NSO Genesis/Mega Drive controller has the wrong PID via Bluetooth...") reads
as an independent, slightly-condensed paraphrase of the same fact pattern our `0038`
documents (same PID values `0x2017`/GENCON, same Main_MiSTer coupling reasoning), not a
verbatim copy — he ported this fix himself, on his own branch, by the time of
`c129b0fac`.

## Conclusion

`tree-diff-2026-09.md` §6's "Re-anchor effort onto `c129b0fac`: Low" framing for this
row was written from the Wave 3 apply-log context (our full series applied cleanly to
*pristine 6.18.38*, which of course lacks this fix) and did not re-verify against his
*current HEAD* specifically for this hunk before populating the Wave 5 candidate table.
The direct re-check the Wave 5 brief asked for shows the gap closed on his side already.

**No `01-*.patch` or `01-*.PR.md` exists in this directory.** Nothing to send upstream
for this item. See `README.md`'s candidate table for the one-line disposition.
