#!/usr/bin/env python3
"""probe-log-analyze.py: decode and summarise dwc2 DDMA split-probe dumps (goal 3b).

WORKSTATION side. Inputs are files or result directories holding
  - ring dumps of /sys/kernel/debug/usb/ffb40000.usb/ddma_probe   (first line "params ...")
  - sampler dumps of .../ddma_sampler                            (first line "state=...")
Formats are those printed by drivers/usb/dwc2/ddma_probe.c (probe commit e458192).
Each directory is one experiment; loose files are grouped by their directory.

Usage: probe-log-analyze.py [--decode] [--ddma 0|1] [--json] <dir|file>...
"""

import argparse
import json
import os
import sys
from collections import Counter, OrderedDict, defaultdict

# HCINTn bits, TRM names (cv_usb_regs.txt HCINT0).
HCINT_BITS = ["xfercompl", "chhltd", "ahberr", "stall", "nak", "ack", "nyet", "xacterr",
              "bblerr", "frmovrun", "datatglerr", "bna", "xcs_xact_err", "desc_lst_rollintr"]
HANDSHAKE = ("ack", "nak", "nyet")
H3_BITS = ("bna", "ahberr", "bblerr", "frmovrun", "desc_lst_rollintr")
XACTPOS = ["mid", "end", "begin", "all"]
EPTYPE = ["ctrl", "iso", "bulk", "int"]
PID = ["DATA0", "DATA2", "DATA1", "MDATA/SETUP"]
QTOKEN = ["in/out", "zlp", "csplit/ping", "halt"]
HALT_STATUS = ["NO_HALT", "COMPLETE", "URB_COMPLETE", "ACK", "NAK", "NYET", "STALL",
               "XACT_ERR", "FRAME_OVERRUN", "BABBLE_ERR", "DATA_TOGGLE_ERR", "AHB_ERR",
               "PERIODIC_INCOMPLETE", "URB_DEQUEUE"]
KINDS = OrderedDict([("H", "halt/irq"), ("D", "dequeue-halt"), ("S", "start"),
                     ("W", "wedge"), ("K", "kill"), ("X", "kill failed"), ("L", "list leaked"),
                     ("F", "URB failed"), ("U", "unaligned"), ("T", "trip")])
STOP_KINDS = "WKXT"


def f(x, sh, w):
    return (x >> sh) & ((1 << w) - 1)


def hcint_names(v):
    n = [HCINT_BITS[i] for i in range(len(HCINT_BITS)) if v & (1 << i)]
    return n


def hcint_str(v):
    return "|".join(hcint_names(v)) or "-"


def dec_hcsplt(v):
    return OrderedDict([("prtaddr", f(v, 0, 7)), ("hubaddr", f(v, 7, 7)),
                        ("xactpos", XACTPOS[f(v, 14, 2)]), ("compsplt", f(v, 16, 1)),
                        ("spltena", f(v, 31, 1))])


def dec_hcchar(v):
    return OrderedDict([("mps", f(v, 0, 11)), ("epnum", f(v, 11, 4)),
                        ("epdir", "in" if f(v, 15, 1) else "out"), ("lspddev", f(v, 17, 1)),
                        ("eptype", EPTYPE[f(v, 18, 2)]), ("ec", f(v, 20, 2)),
                        ("devaddr", f(v, 22, 7)), ("oddfrm", f(v, 29, 1)),
                        ("chdis", f(v, 30, 1)), ("chena", f(v, 31, 1))])


def dec_hctsiz(v, ddma):
    if ddma:
        return OrderedDict([("schinfo", "0x%02x" % f(v, 0, 8)), ("ntd", f(v, 8, 8)),
                            ("pid", PID[f(v, 29, 2)]), ("dopng", f(v, 31, 1))])
    return OrderedDict([("xfersize", f(v, 0, 19)), ("pktcnt", f(v, 19, 10)),
                        ("pid", PID[f(v, 29, 2)]), ("dopng", f(v, 31, 1))])


def dec_hcdma(v, ddma):
    if ddma:
        return OrderedDict([("list", "0x%08x" % (v & ~0x1ff & 0xffffffff)), ("ctd", f(v, 3, 6))])
    return OrderedDict([("addr", "0x%08x" % v)])


def dec_desc(v):
    return OrderedDict([("a", f(v, 31, 1)), ("sts", ["ok", "pkterr", "rsvd2", "rsvd3"][f(v, 28, 2)]),
                        ("eol", f(v, 26, 1)), ("ioc", f(v, 25, 1)), ("sup", f(v, 24, 1)),
                        ("alt_qtd", f(v, 23, 1)), ("qtd_off", f(v, 17, 6)),
                        ("n_bytes", f(v, 0, 17))])


def desc_str(v):
    d = dec_desc(v)
    return "A=%d STS=%s EOL=%d IOC=%d SUP=%d n=%d" % (d["a"], d["sts"], d["eol"], d["ioc"],
                                                       d["sup"], d["n_bytes"])


# Queue-top depths on this DWC_otg 2.93a core (e1b-analysis.md sec A.4): GNPTXSTS follows the
# TRM (8-entry non-periodic queue); HPTXSTS does not (16-entry periodic queue, see dec_ptxqtop).
NP_QDEPTH = 8
P_QDEPTH = 16


def dec_qtop(v):
    """GNPTXSTS (non-periodic queue top). Matches the TRM layout; validated on this silicon."""
    return OrderedDict([("qspace", f(v, 16, 8)), ("terminate", f(v, 24, 1)),
                        ("token", f(v, 25, 2)), ("chnum", f(v, 27, 4)), ("odd", f(v, 31, 1))])


def dec_ptxqtop(v):
    """HPTXSTS (periodic queue top) on this core: channel is [31:28], not the TRM's [30:27].
    [27:24] does not decode to a TRM token/terminate pair here (e1b-analysis.md sec A.4), so the
    token type is not reported. qspace stays at [23:16], empirically still free-slot count."""
    return OrderedDict([("qspace", f(v, 16, 8)), ("chnum", f(v, 28, 4))])


def qtop_decode(qname, v):
    """Decode a ptx (HPTXSTS) or nptx (GNPTXSTS) queue-top word. Returns (fields, token_name,
    empty), where token_name is 'raw' for ptx (undecodable here) and empty follows the per-queue
    depth: a stale/empty top must not be read as a live entry."""
    if qname == "ptx":
        t = dec_ptxqtop(v)
        return t, "raw", t["qspace"] >= P_QDEPTH
    t = dec_qtop(v)
    return t, QTOKEN[t["token"]], t["qspace"] >= NP_QDEPTH


def dec_hfnum(v):
    frnum = f(v, 0, 16)
    return OrderedDict([("frnum", frnum), ("frame", frnum >> 3), ("uframe", frnum & 7),
                        ("frrem", f(v, 16, 16))])


def hfnum_delta_ns(hf_later, hf_earlier):
    """HS bus time between two HFNUM reads, from FRNUM (uframe counter, wraps at 0x3fff) and
    FRREM (60 MHz clocks left in the uframe; one uframe = 7500 clocks = 125us; e1b-analysis.md
    sec A.1). FRREM counts down within a uframe, so elapsed = uframes*7500 + (rem0 - rem1)."""
    a, b = dec_hfnum(hf_earlier), dec_hfnum(hf_later)
    uframes = (b["frnum"] - a["frnum"]) & 0x3fff
    clocks = uframes * 7500 + (a["frrem"] - b["frrem"])
    return clocks * (1000.0 / 60.0)


def kv_line(line):
    d = OrderedDict()
    for t in line.split():
        if "=" in t:
            k, v = t.split("=", 1)
            d[k] = v
    return d


def h(v):
    return int(v, 16) if v.startswith(("0x", "0X")) else int(v)


def parse_ring(lines):
    r = {"params": {}, "counters": {}, "hcdmab518": None, "chena_mask": None, "records": []}
    for ln in lines:
        ln = ln.strip()
        if not ln:
            continue
        if ln.startswith("params "):
            r["params"] = kv_line(ln)
        elif ln.startswith("counters "):
            r["counters"] = {k: int(v) for k, v in kv_line(ln).items()}
        elif ln.startswith("hcdmab518"):
            rest = ln.split()[1:]
            r["hcdmab518"] = "skipped" if rest and rest[0] == "skipped:" else [h(x) for x in rest]
        elif ln.startswith("chena_mask="):
            r["chena_mask"] = h(ln.split("=", 1)[1])
        elif ln.startswith("t="):
            kv = kv_line(ln)
            rec = {"t": int(kv["t"]), "k": kv.get("k", "?")}
            for k in ("ch", "dev", "ep", "split", "psplit", "ddma", "ping", "errst", "hs", "ctd"):
                if k in kv:
                    rec[k] = int(kv[k])
            rec["type"] = kv.get("type")
            rec["dir"] = kv.get("dir")
            for k in ("hfnum", "hcint", "msk", "hcsplt", "hcchar", "hctsiz", "hcdma", "hcdmab",
                      "hcdmab518", "ptx", "nptx", "d0", "d1", "d2", "dc", "x"):
                if k in kv:
                    rec[k] = h(kv[k])
            r["records"].append(rec)
    return r


def parse_sampler(lines):
    s = {"hdr": {}, "cols": [], "rows": []}
    for ln in lines:
        ln = ln.strip()
        if not ln:
            continue
        if ln.startswith("state="):
            s["hdr"] = kv_line(ln)
        elif ln.startswith("#"):
            s["cols"] = ln[1:].split()
        else:
            vals = ln.split()
            if s["cols"] and len(vals) == len(s["cols"]):
                s["rows"].append({c: h(v) for c, v in zip(s["cols"], vals)})
    return s


def classify_file(path):
    try:
        with open(path, errors="replace") as fh:
            lines = fh.readlines()
    except OSError:
        return None, None
    first = next((ln for ln in lines if ln.strip()), "")
    if first.startswith("params "):
        return "ring", parse_ring(lines)
    if first.startswith("state="):
        return "sampler", parse_sampler(lines)
    return None, None


def decode_record(rec, ddma):
    parts = ["t=%d k=%s(%s) ch=%s dev=%s ep=%s %s/%s split=%s psplit=%s hs=%s" % (
        rec["t"], rec["k"], KINDS.get(rec["k"], "?"), rec.get("ch"), rec.get("dev"),
        rec.get("ep"), rec.get("type"), rec.get("dir"), rec.get("split"), rec.get("psplit"),
        HALT_STATUS[rec["hs"]] if rec.get("hs", 99) < len(HALT_STATUS) else rec.get("hs"))]
    if "hcint" in rec:
        parts.append("hcint=%s" % hcint_str(rec["hcint"]))
    if "hcsplt" in rec:
        parts.append("hcsplt{%s}" % " ".join("%s=%s" % kv for kv in dec_hcsplt(rec["hcsplt"]).items()))
    if "hcchar" in rec:
        c = dec_hcchar(rec["hcchar"])
        parts.append("hcchar{dev=%d ep=%d%s %s mps=%d ec=%d chena=%d chdis=%d}" % (
            c["devaddr"], c["epnum"], c["epdir"], c["eptype"], c["mps"], c["ec"], c["chena"],
            c["chdis"]))
    if "hctsiz" in rec:
        parts.append("hctsiz{%s}" % " ".join("%s=%s" % kv for kv in dec_hctsiz(rec["hctsiz"], ddma).items()))
    if "hcdma" in rec and ddma:
        parts.append("ctd=%d" % dec_hcdma(rec["hcdma"], True)["ctd"])
    if "hfnum" in rec:
        hf = dec_hfnum(rec["hfnum"])
        parts.append("fr=%d uf=%d" % (hf["frame"], hf["uframe"]))
    for q in ("ptx", "nptx"):
        if q in rec:
            t, tok, empty = qtop_decode(q, rec[q])
            if empty:
                parts.append("%s{ch=%d qs=%d empty}" % (q, t["chnum"], t["qspace"]))
            else:
                parts.append("%s{tok=%s ch=%d qs=%d}" % (q, tok, t["chnum"], t["qspace"]))
    for d in ("d0", "d1", "d2", "dc"):
        if d in rec:
            parts.append("%s{%s}" % (d, desc_str(rec[d])))
    parts.append("x=%s" % decode_x(rec))
    return " ".join(parts)


def decode_x(rec):
    x = rec.get("x", 0)
    k = rec["k"]
    if k == "S":
        return "schinfo=0x%02x" % (x & 0xff)
    if k == "D":
        return "halt_status=%s" % (HALT_STATUS[x] if x < len(HALT_STATUS) else x)
    if k == "W":
        if x < 0x100:
            return "halt_status=%s%s" % (HALT_STATUS[x] if x < len(HALT_STATUS) else x,
                                         " (free guard)" if x == 0 else "")
        return "wait frames=%d us=%d" % (x >> 16, x & 0xffff)
    if k == "F":
        hs = f(x, 8, 8)
        return "hcint=%s halt=%s errs=%d" % (hcint_str(x >> 16),
                                             HALT_STATUS[hs] if hs < len(HALT_STATUS) else hs,
                                             x & 0xff)
    if k == "K":
        return "hprt0=0x%08x" % x
    if k == "X":
        return "ret=%d" % (x - (1 << 32) if x & 0x80000000 else x)
    if k == "L":
        return "list=0x%08x" % x
    if k == "U":
        return "xfer_dma=0x%08x" % x
    if k == "T":
        return "rate=%d/s" % x
    return "0x%08x" % x


def summarise_ring(r, ddma):
    recs = r["records"]
    out = OrderedDict()
    out["params"] = r["params"]
    out["counters"] = r["counters"]
    cm = r["chena_mask"]
    out["chena_mask"] = None if cm is None else "0x%04x %s" % (cm, [i for i in range(16) if cm >> i & 1])
    out["records"] = len(recs)
    out["kinds"] = dict(Counter(x["k"] for x in recs))
    c = r["counters"]
    stops = [k for k in ("wedges", "kills", "kill_fails", "trips") if c.get(k, 0) > 0]
    stops += [k for k in ("tripped", "dead", "reset_failed") if c.get(k, 0)]
    stops += ["%s-record" % k for k in STOP_KINDS if any(x["k"] == k for x in recs)]
    out["stop_criteria"] = stops
    out["power_cycle_required"] = bool(c.get("reset_failed") or c.get("kill_fails")
                                       or any(x["k"] == "X" for x in recs))

    halts = [x for x in recs if x["k"] in ("H", "D") and "hcint" in x]
    groups = OrderedDict()
    for name, sp_, dm_ in (("ddma_split", 1, 1), ("ddma_nonsplit", 0, 1),
                           ("buffer_split", 1, 0), ("buffer_nonsplit", 0, 0)):
        g = [x for x in halts if x.get("split") == sp_ and x.get("ddma") == dm_]
        if not g:
            continue
        bits = Counter()
        for x in g:
            for n in hcint_names(x["hcint"]):
                bits[n] += 1
        # Split signatures carry COMPSPLT: E-1 separates SSPLIT and CSPLIT halts by it
        sigs = Counter(("%s compsplt=%d %s" % (x["k"], f(x["hcsplt"], 16, 1), hcint_str(x["hcint"])))
                       if sp_ else "%s %s" % (x["k"], hcint_str(x["hcint"])) for x in g)
        groups[name] = OrderedDict([
            ("records", len(g)),
            ("bits", dict(bits)),
            ("handshake_latched", {n: bits.get(n, 0) for n in HANDSHAKE}),
            ("signatures", dict(sigs.most_common(12)))])
    out["halt_groups"] = groups

    sp = [x for x in recs if x.get("split") == 1 and "hcsplt" in x]
    out["split_hcsplt"] = OrderedDict([
        ("spltena", dict(Counter(f(x["hcsplt"], 31, 1) for x in sp))),
        ("compsplt", dict(Counter(f(x["hcsplt"], 16, 1) for x in sp))),
        ("hub_port", dict(Counter("%d:%d" % (f(x["hcsplt"], 7, 7), f(x["hcsplt"], 0, 7)) for x in sp)))])
    # Only GNPTXSTS (nptx) decodes a token type on this core; HPTXSTS (ptx) cannot (dec_ptxqtop),
    # so it cannot support a "type 2 = CSPLIT" claim and is left out of this check entirely.
    q2 = []
    for x in recs:
        if "ch" not in x or "nptx" not in x:
            continue
        t, _, empty = qtop_decode("nptx", x["nptx"])
        if not empty and t["token"] == 2 and t["chnum"] == x["ch"]:
            q2.append((x["k"], x["ch"], "nptx", x.get("split")))
    out["qtop_csplit_on_own_channel"] = dict(Counter("%s ch%d %s split=%s" % v for v in q2))

    dsum = Counter()
    for x in recs:
        if x["k"] == "H" and "d0" in x:
            d = dec_desc(x["d0"])
            dsum["%s %s/%s split=%s: A=%d STS=%s EOL=%d n=%d" % (
                hcint_str(x["hcint"]), x.get("type"), x.get("dir"), x.get("split"), d["a"],
                d["sts"], d["eol"], d["n_bytes"])] += 1
    out["descriptor_outcomes_d0"] = dict(dsum.most_common(20))
    pids = Counter()
    for x in recs:
        if x.get("split") == 1 and "hctsiz" in x:
            pids["%s/%s %s" % (x.get("type"), x.get("dir"), PID[f(x["hctsiz"], 29, 2)])] += 1
    out["split_pid_at_record"] = dict(pids)
    out["special"] = [decode_record(x, ddma) for x in recs if x["k"] in "WKXLFUT"][:40]
    out["starts"] = dict(Counter("ch%d %s/%s spltena=%d compsplt=%d ec=%d schinfo=0x%02x" % (
        x["ch"], x.get("type"), x.get("dir"), f(x["hcsplt"], 31, 1), f(x["hcsplt"], 16, 1),
        f(x["hcchar"], 20, 2), x["x"] & 0xff) for x in recs if x["k"] == "S"))
    out["hints"] = ring_hints(recs, c)
    return out


def ring_hints(recs, c):
    """Signatures from the E1b decision table (probe-design.md section 7). Hints only."""
    hints = []
    recs = [x for x in recs if x.get("ddma") == 1]
    sp = [x for x in recs if x.get("split") == 1 and x["k"] in ("H", "D") and "hcint" in x]
    if not sp:
        return ["no halt records on descriptor-DMA split channels"]
    bits = Counter()
    for x in sp:
        for n in hcint_names(x["hcint"]):
            bits[n] += 1
    if bits["nyet"]:
        hints.append("raw NYET on a split channel: the hardware issued a CSPLIT (never H1); "
                     "at least H2-partial")
    for x in recs:
        if x.get("split") == 1 and "ch" in x and "nptx" in x:
            t, _, empty = qtop_decode("nptx", x["nptx"])
            if not empty and t["token"] == 2 and t["chnum"] == x["ch"]:
                hints.append("queue top type 2 (CSPLIT) on the split channel itself: CSPLIT queued")
                break
    if bits["stall"] or c.get("stalls", 0):
        hints.append("STALL on a split channel: only a CSPLIT returns a device STALL (H2 evidence)")
    ok_in = [x for x in sp if x["k"] == "H" and x["hcint"] & 1 and "d0" in x
             and not x["d0"] & 0xb0000000 and x.get("dir") == "in"]
    if ok_in:
        hints.append("%d XFERCOMPL halts with an IN descriptor retired A=0 STS=ok: data may have "
                     "moved (H2) or retired on the SSPLIT ACK (H1a); check usbmon actual length "
                     "and bytes" % len(ok_in))
    pkterr_xc = [x for x in sp if x["k"] == "H" and x["hcint"] & 1 and "d0" in x
                 and f(x["d0"], 28, 2) == 1]
    if pkterr_xc:
        hints.append("%d XFERCOMPL halts with d0 STS=PKTERR: H3-type (usbmon -115)" % len(pkterr_xc))
    h0 = [x for x in sp if x["k"] == "H" and x["hcint"] & 0x1000 and not x["hcint"] & 0x20]
    if h0:
        hints.append("%d XCS_XACT halts without ACK: H0 signature if ACK latches (see E0)" % len(h0))
    h1c = [x for x in sp if x["k"] == "H" and x["hcint"] & 0x22 == 0x22 and not x["hcint"] & 0x41]
    if h1c:
        hints.append("%d CHHLTD|ACK halts without XFERCOMPL/NYET: H1c (E-1 SSPLIT signature)" % len(h1c))
    only_d = [x for x in sp if x["k"] == "D" and x["hcint"] & 0x20]
    if only_d and not any(x["k"] == "H" for x in sp):
        hints.append("ACK only in dequeue records, no halts: H1b (SSPLIT loop)")
    h3 = [n for n in H3_BITS if bits[n]]
    if h3:
        hints.append("H3-type bits on split channels: %s" % ",".join(h3))
    return hints


def calc_is_calc_ring(fn):
    return fn.startswith("calc-ring")


def calc_is_calc_sampler(fn):
    return fn.startswith("calc-sampler")


def calc_phase(rec):
    """Classify a control-split ring record's USB stage for the E-1c calibration (buffer-DMA
    control split): SETUP is OUT with HCTSIZ PID=MDATA/SETUP; DATA is the IN stage; STATUS is
    the remaining OUT (zero-length ack). Matches the calibration's SETUP/DATA-IN/STATUS-OUT shape
    (e1b-analysis.md). Must be called on the channel's "S" (start) record: by the halt, HCTSIZ's
    PID has already moved off MDATA/SETUP (e1b-analysis.md sec A.2), so SETUP would misclassify
    as STATUS if read from the halt instead. Returns None for anything else."""
    if rec.get("type") != "ctrl" or rec.get("split") != 1:
        return None
    if rec.get("dir") == "in":
        return "DATA"
    if "hctsiz" in rec and f(rec["hctsiz"], 29, 2) == 3:
        return "SETUP"
    return "STATUS"


def fmt_counter(c):
    return ",".join("%s:%d" % (k, v) for k, v in sorted((str(k), v) for k, v in c.items())) or "none"


def fmt_stats(vals):
    if not vals:
        return "none"
    return "n=%d mean=%.1f min=%.1f max=%.1f" % (len(vals), sum(vals) / len(vals), min(vals), max(vals))


def summarise_calc(g):
    """E-1c: buffer-DMA control-split calibration (calc-ring.txt / calc-sampler-*.txt). Per
    control-transfer phase (SETUP/DATA/STATUS), tallies the HCSPLT compsplt value and raw HCINT
    bits seen at each halt, and the channel-start-to-halt time (HFNUM-based, see hfnum_delta_ns).
    Also tallies every non-empty GNPTXSTS queue-top token type seen on a split channel's own
    queue entry, split by whether that channel was mid-SSPLIT or mid-CSPLIT (HCSPLT compsplt) at
    the time, to learn how SSPLIT vs CSPLIT show up in the non-periodic queue. Returns None if no
    calc-* files are present in this experiment."""
    recs = [x for fn, r in g["ring"] for x in r["records"] if calc_is_calc_ring(fn)]
    has_calc_sampler = any(calc_is_calc_sampler(fn) for fn, _ in g["sampler"])
    if not recs and not has_calc_sampler:
        return None
    out = OrderedDict()
    by_ch = defaultdict(list)
    for x in recs:
        if "ch" in x:
            by_ch[x["ch"]].append(x)
    phase_names = ("SETUP", "DATA", "STATUS")
    phases = OrderedDict((p, OrderedDict([("halts", 0), ("compsplt", Counter()),
                                          ("hcint", Counter()), ("to_halt_us", [])]))
                         for p in phase_names)
    setup_to_halt_us = {0: [], 1: []}
    ssplit_types, csplit_types = Counter(), Counter()
    for ch, xs in sorted(by_ch.items()):
        xs.sort(key=lambda r: r["t"])
        start, phase = None, None
        for x in xs:
            if "nptx" in x and "hcsplt" in x and x.get("split") == 1:
                t, tok, empty = qtop_decode("nptx", x["nptx"])
                if not empty and t["chnum"] == ch:
                    (csplit_types if f(x["hcsplt"], 16, 1) else ssplit_types)[tok] += 1
            if x["k"] == "S":
                start, phase = x, calc_phase(x)
                continue
            if x["k"] in ("H", "D") and "hcint" in x and phase:
                cs = f(x["hcsplt"], 16, 1) if "hcsplt" in x else None
                p = phases[phase]
                p["halts"] += 1
                p["compsplt"][cs] += 1
                p["hcint"][hcint_str(x["hcint"])] += 1
                if start is not None and "hfnum" in x and "hfnum" in start:
                    us = round(hfnum_delta_ns(x["hfnum"], start["hfnum"]) / 1000.0, 2)
                    p["to_halt_us"].append(us)
                    if phase == "SETUP" and cs in (0, 1):
                        setup_to_halt_us[cs].append(us)
                start, phase = None, None
    out["phases"] = OrderedDict(
        (p, OrderedDict([("halts", d["halts"]), ("compsplt", dict(d["compsplt"])),
                         ("hcint", dict(d["hcint"])), ("to_halt_us_sample", d["to_halt_us"][:20])]))
        for p, d in phases.items())
    out["ssplit_qtop_types"] = dict(ssplit_types)
    out["csplit_qtop_types"] = dict(csplit_types)
    out["setup_ssplit_to_halt_us"] = setup_to_halt_us[0]
    out["setup_csplit_to_halt_us"] = setup_to_halt_us[1]
    return out


def summarise_sampler(s, ddma):
    hd = s["hdr"]
    rows = s["rows"]
    out = OrderedDict()
    out["header"] = hd
    out["samples"] = len(rows)
    ov = int(hd.get("overruns", "0"))
    out["overruns"] = ov
    if ov:
        out["warning"] = "period did not hold (overruns=%d)" % ov
    if hd.get("mode") == "g":
        tok = Counter()
        for r in rows:
            for q in ("ptx", "nptx"):
                t, nm, empty = qtop_decode(q, r[q])
                if not empty:
                    tok["%s ch%d %s" % (q, t["chnum"], nm)] += 1
        out["qtop"] = dict(tok.most_common())
        out["haint_channels"] = sorted({i for r in rows for i in range(16) if r["haint"] >> i & 1})
        return out
    ch = int(hd.get("chan", "-1"))
    bits = OrderedDict()
    for r in rows:
        for n in hcint_names(r["hcint"]):
            bits.setdefault(n, r["dt_ns"])
    out["hcint_first_seen_ns"] = bits
    out["handshake_seen"] = {n: n in bits for n in HANDSHAKE}

    def trans(key, fn):
        t, prev = [], None
        for r in rows:
            v = fn(r[key])
            if v != prev:
                t.append((r["dt_ns"], dec_hfnum(r["hfnum"])["uframe"], v))
                prev = v
        return t

    cs = trans("hcsplt", lambda v: f(v, 16, 1))
    out["compsplt_values"] = sorted({v for _, _, v in cs})
    out["compsplt_changed"] = len(cs) > 1
    out["compsplt_transitions"] = cs[:32]
    out["spltena_values"] = sorted({f(r["hcsplt"], 31, 1) for r in rows})
    out["chena_transitions"] = trans("hcchar", lambda v: f(v, 31, 1))[:32]
    if ddma:
        out["ctd_transitions"] = trans("hcdma", lambda v: f(v, 3, 6))[:32]
        out["ntd_values"] = sorted({f(r["hctsiz"], 8, 8) for r in rows})
    out["pid_transitions"] = [(t, uf, PID[v]) for t, uf, v in trans("hctsiz", lambda v: f(v, 29, 2))][:32]
    own = []
    tok = Counter()
    for r in rows:
        for q in ("ptx", "nptx"):
            t, nm, empty = qtop_decode(q, r[q])
            if empty:
                continue
            tok["%s ch%d %s" % (q, t["chnum"], nm)] += 1
            # Only GNPTXSTS (nptx) decodes a token type here; HPTXSTS (ptx) cannot (dec_ptxqtop).
            if q == "nptx" and t["token"] == 2 and t["chnum"] == ch:
                own.append((r["dt_ns"], dec_hfnum(r["hfnum"])["uframe"], q))
    out["qtop"] = dict(tok.most_common(12))
    out["csplit_qtop_on_channel"] = own[:32]
    out["csplit_qtop_on_channel_n"] = len(own)
    return out


def collect(paths):
    groups = defaultdict(lambda: {"ring": [], "sampler": []})
    for p in paths:
        if os.path.isdir(p):
            for root, _, files in os.walk(p):
                for fn in sorted(files):
                    fp = os.path.join(root, fn)
                    kind, obj = classify_file(fp)
                    if kind:
                        groups[root][kind].append((fn, obj))
        else:
            kind, obj = classify_file(p)
            if kind:
                groups[os.path.dirname(p) or "."][kind].append((os.path.basename(p), obj))
    return groups


def infer_ddma(g, forced):
    if forced is not None:
        return forced
    for _, r in g["ring"]:
        if "desc_dma" in r["params"]:
            return int(r["params"]["desc_dma"])
    return 1


def experiment_summary(g, ddma):
    ex = OrderedDict()
    ex["ddma"] = ddma
    ex["rings"] = OrderedDict((fn, summarise_ring(r, ddma)) for fn, r in g["ring"])
    ex["samplers"] = OrderedDict((fn, summarise_sampler(s, ddma)) for fn, s in g["sampler"])
    ex["calc"] = summarise_calc(g)
    q = OrderedDict()
    q["handshake_latched_ddma"] = any(
        sum(gr.get("handshake_latched", {}).values()) > 0
        for r in ex["rings"].values() for k, gr in r["halt_groups"].items() if k.startswith("ddma")
    ) or any(any(sm.get("handshake_seen", {}).values()) and ddma for sm in ex["samplers"].values())
    q["compsplt_changed_in_sampler"] = any(sm.get("compsplt_changed") for sm in ex["samplers"].values())
    q["csplit_qtop_seen"] = any(r["qtop_csplit_on_own_channel"] for r in ex["rings"].values()) or any(
        sm.get("csplit_qtop_on_channel_n", 0) for sm in ex["samplers"].values()) or any(
        any("csplit" in k for k in sm.get("qtop", {})) for sm in ex["samplers"].values()
        if sm["header"].get("mode") == "g")
    q["stop_criteria"] = sorted({s for r in ex["rings"].values() for s in r["stop_criteria"]})
    q["power_cycle_required"] = any(r["power_cycle_required"] for r in ex["rings"].values())
    q["hints"] = sorted({h for r in ex["rings"].values() for h in r["hints"]})
    ex["answers"] = q
    return ex


def print_text(res, out):
    w = out.write
    for d, ex in res.items():
        w("#### experiment %s (decode %s)\n" % (d, "S/G" if ex["ddma"] else "buffer"))
        a = ex["answers"]
        w("ANSWER handshake_latched_ddma=%s compsplt_changed=%s csplit_qtop_seen=%s\n" % (
            int(a["handshake_latched_ddma"]), int(a["compsplt_changed_in_sampler"]),
            int(a["csplit_qtop_seen"])))
        w("ANSWER stop_criteria=%s power_cycle_required=%d\n" % (
            ",".join(a["stop_criteria"]) or "none", int(a["power_cycle_required"])))
        for hnt in a["hints"]:
            w("HINT %s\n" % hnt)
        for fn, r in ex["rings"].items():
            w("\n== ring %s: %d records %s\n" % (fn, r["records"], r["kinds"]))
            w("params %s\n" % " ".join("%s=%s" % kv for kv in r["params"].items()))
            w("counters %s\n" % " ".join("%s=%s" % kv for kv in r["counters"].items()))
            w("chena_mask %s\n" % r["chena_mask"])
            for gname, gr in r["halt_groups"].items():
                w("[%s] %d halt records; handshake %s\n" % (gname, gr["records"], gr["handshake_latched"]))
                for sig, n in gr["signatures"].items():
                    w("    %5d  %s\n" % (n, sig))
            w("split hcsplt %s\n" % dict(r["split_hcsplt"]))
            w("qtop CSPLIT on own channel: %s\n" % (r["qtop_csplit_on_own_channel"] or "none"))
            for k, n in r["starts"].items():
                w("start %5d  %s\n" % (n, k))
            for k, n in r["descriptor_outcomes_d0"].items():
                w("d0 %5d  %s\n" % (n, k))
            for k, n in r["split_pid_at_record"].items():
                w("pid %5d  %s\n" % (n, k))
            for s in r["special"]:
                w("! %s\n" % s)
        for fn, s in ex["samplers"].items():
            hd = s["header"]
            w("\n== sampler %s: mode=%s chan=%s samples=%d overruns=%d stop=%s\n" % (
                fn, hd.get("mode"), hd.get("chan"), s["samples"], s["overruns"], hd.get("stop_reason")))
            if "warning" in s:
                w("WARNING %s\n" % s["warning"])
            for k in ("qtop", "haint_channels", "hcint_first_seen_ns", "handshake_seen",
                      "compsplt_values", "compsplt_changed", "compsplt_transitions",
                      "spltena_values", "chena_transitions", "ctd_transitions", "ntd_values",
                      "pid_transitions", "csplit_qtop_on_channel_n", "csplit_qtop_on_channel"):
                if k in s:
                    w("%s %s\n" % (k, s[k]))
        c = ex.get("calc")
        if c:
            w("ANSWER calc_ssplit_qtop_types=%s calc_csplit_qtop_types=%s\n" % (
                fmt_counter(c["ssplit_qtop_types"]), fmt_counter(c["csplit_qtop_types"])))
            w("ANSWER calc_setup_ssplit_to_halt_us=%s calc_setup_csplit_to_halt_us=%s\n" % (
                fmt_stats(c["setup_ssplit_to_halt_us"]), fmt_stats(c["setup_csplit_to_halt_us"])))
            w("\n== E-1c control-split calibration\n")
            for p, pd in c["phases"].items():
                w("[%s] %d halts; compsplt %s; hcint %s\n" % (
                    p, pd["halts"], dict(pd["compsplt"]), dict(pd["hcint"])))
                if pd["to_halt_us_sample"]:
                    w("    to_halt_us %s\n" % pd["to_halt_us_sample"])
        w("\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--decode", action="store_true", help="print every ring record decoded")
    ap.add_argument("--ddma", type=int, choices=(0, 1), help="HCTSIZ/HCDMA layout (default: from ring params)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    groups = collect(a.paths)
    if not groups:
        sys.exit("probe-log-analyze: no ddma_probe or ddma_sampler dumps found")
    res = OrderedDict()
    for d in sorted(groups):
        g = groups[d]
        ddma = infer_ddma(g, a.ddma)
        if a.decode:
            for fn, r in g["ring"]:
                for rec in r["records"]:
                    ddm = rec.get("ddma", ddma) if a.ddma is None else a.ddma
                    print("%s: %s" % (fn, decode_record(rec, ddm)))
            continue
        res[d] = experiment_summary(g, ddma)
    if a.decode:
        return
    if a.json:
        json.dump(res, sys.stdout, indent=1)
        sys.stdout.write("\n")
    else:
        print_text(res, sys.stdout)


if __name__ == "__main__":
    main()
