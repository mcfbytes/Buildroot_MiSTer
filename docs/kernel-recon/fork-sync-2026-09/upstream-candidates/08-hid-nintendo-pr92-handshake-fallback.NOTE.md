> **Outcome: POSTED AND ACCEPTED.** Posted to
> [MiSTer-devel/Linux-Kernel_MiSTer#92](https://github.com/MiSTer-devel/Linux-Kernel_MiSTer/pull/92)
> by @mcfbytes on 2026-09-11. The submitter adopted the `usb_handshook` form in PR head
> `fd682da6a5`, and that is what merged on 2026-09-12 as
> [`66ba034e3`](https://github.com/MiSTer-devel/Linux-Kernel_MiSTer/commit/66ba034e3b5d362de108917ea9b6c92235ea4ec6),
> whose message says "That regression was spotted in review by mcfbytes." Upstream and our
> `0049` now carry the same code.
>
> One correction from the thread, re-verified against `git show c129b0fac:drivers/hid/hid-nintendo.c`:
> on this base the *fatal* step is the **second handshake**, not the baudrate command — the
> fork downgrades a `JC_USB_CMD_BAUDRATE_3M` failure to `hid_warn` and continues. The
> conclusion below ("probe fails where vanilla succeeded") is unchanged. The text below is kept
> as it was posted.

**Title:** hid-nintendo: restore the no-first-handshake fallback this reorder drops

**Body:**

Vanilla (v6.18.38, `drivers/hid/hid-nintendo.c:2467-2468`):

    /* if handshake command fails, assume ble pro controller */
    if (joycon_using_usb(ctlr) && !joycon_send_usb(ctlr, JC_USB_CMD_HANDSHAKE, HZ)) {

only runs baudrate/handshake-confirm/no-timeout when the *first* handshake
succeeds; on failure (non-chrggrip) it falls through untouched and probes at
the default baud. This PR re-guards that same block as `if
(joycon_using_usb(ctlr) && !joycon_device_is_8bitdo(ctlr))`, dropping the
"first handshake succeeded" condition entirely.

**Affected:** any USB-bus `057e:2009`/`2017`/`200e` device that does not
answer `JC_USB_CMD_HANDSHAKE` on the first try — not just 8BitDo hardware.
It now unconditionally gets `JC_USB_CMD_BAUDRATE_3M` and a second, *fatal*
handshake it was never going to answer either, so probe fails where vanilla
would have succeeded.

**Fix:** track the first handshake's own result — add `bool usb_handshook =
false;`, set `true` only in the first handshake's success body, and gate
the baudrate block on `usb_handshook && !joycon_device_is_8bitdo(ctlr)`.
Keeps this PR's intent (read_info before baudrate; skip both for 8BitDo)
while restoring the vanilla fallback for everything else.
