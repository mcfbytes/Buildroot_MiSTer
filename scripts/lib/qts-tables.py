#!/usr/bin/env python3
"""qts-tables.py -- pack the seven Altera QTS handoff tables
(docs/uboot-mainline-port.md Sec 3.2a) out of a `qts/*.h` header directory and
search for each one inside SPL copy 0 (the first 0x10000 bytes) of one or more
U-Boot images.

WHY THIS IS PYTHON, NOT sh (sanctioned style exception -- docs/uboot-tasks.md
U4b). Every other check script in this repo is POSIX sh (scripts/
check-zimage-dtb.sh house style): no dependency beyond the host shell and
coreutils. This one packs C initialiser lists into little-endian machine words
and does a substring search over an 8 KiB-ish binary window -- doable in sh
with od/printf, but not legibly, and Buildroot already requires host python3
for its own build (support/scripts/*, and this repo's own scripts/
gen-db-json.py, scripts/check-db-json-schema.py, scripts/db_entity_contract.py
already run under it in CI). So this one piece is a small python3 module,
invoked from the POSIX sh wrapper (scripts/check-uboot-handoff.sh), which does
everything else -- argument validation, ok()/bad() reporting, exit-code
discipline -- in the repo's usual house style.

WHERE THE PARSER CAME FROM. The C-initialiser-list extraction below (parse_arrays)
is lifted, not reinvented, from the research spike's own diff tool:
/mnt/source/uboot-mainline/verify-qts/qtsdiff.py (outside the repo, gitignored by
being outside it; never committed). Only the array half is kept -- qtsdiff.py
also diffs #define scalars between two trees, which this tool has no need for,
since it is proving *presence* of specific named arrays in a binary, not
diffing two source trees against each other. The comment-stripping and
brace-balancing logic is otherwise unchanged from that tool.

WHAT THIS PROVES AND DOES NOT. Per plan Sec 3.2a: packing a table byte-identically
and finding it inside SPL copy 0 proves the SPL was built from a `qts/*.h` tree
whose value for that table matches what was packed. It says nothing about
*where* in the image it lives (offsets are reported, never compared between
images -- code layout differs) and nothing about the scalar #defines that never
appear in the binary as byte strings (those compile to instruction immediates;
Sec 3.2a is explicit that this method cannot touch them).

THE SEVEN TABLES (name -> C element type -> packing):
  sys_mgr_init_table        u8      raw bytes, one byte per element
  iocsr_scan_chain0_table   u32     little-endian, 4 bytes per element
  iocsr_scan_chain1_table   u32     little-endian, 4 bytes per element
  iocsr_scan_chain2_table   u32     little-endian, 4 bytes per element
  iocsr_scan_chain3_table   u32     little-endian, 4 bytes per element
  ac_rom_init               u32     little-endian, 4 bytes per element
  inst_rom_init             u32     little-endian, 4 bytes per element

Usage:
    qts-tables.py <qts-dir> <image> [<image> ...]

    <qts-dir>  a directory containing the four `qts/*.h` headers (any subset
               that between them define all seven tables above; which .h file
               holds which table is not assumed -- every *.h directly inside
               the directory is parsed and their array definitions merged).
    <image>    one or more U-Boot images (a built `u-boot-with-spl.sfp` or a
               stock `uboot.img`). SPL copy 0 is taken as the image's own
               first 0x10000 bytes, per boot-chain's four-copy SPL layout.

Output (stdout, tab-separated, one line per table x image, table order fixed
as listed above, image order as given on the command line):

    <table>\t<image>\t<FOUND|MISSING>\t<offset-hex-or-->\t<n-bytes>\t<n-elements>

followed by one summary line:

    SUMMARY\ttables=<n>\timages=<n>\tmissing=<n>

Exit: 0 = every table found in every image, 1 = at least one (table, image)
pair is missing -- a real assertion failure, not a crash, 2 = usage/parse/IO
error (bad arguments, a table not DEFINED anywhere under <qts-dir>, an image
that does not exist or is shorter than the SPL-copy window).
"""

import glob
import os
import re
import struct
import sys

SPL_COPY_SIZE = 0x10000  # boot-chain: four byte-identical 64 KiB SPL copies

# (name, C element type). Order matches docs/uboot-mainline-port.md Sec 3.2a's table.
TABLES = [
    ("sys_mgr_init_table", "u8"),
    ("iocsr_scan_chain0_table", "u32"),
    ("iocsr_scan_chain1_table", "u32"),
    ("iocsr_scan_chain2_table", "u32"),
    ("iocsr_scan_chain3_table", "u32"),
    ("ac_rom_init", "u32"),
    ("inst_rom_init", "u32"),
]


def parse_arrays(path):
    """Extract every `TYPE name[] = { ... };` initialiser in a C header as
    {name: [raw element token, ...]}. Lifted from qtsdiff.py's parse() (see
    module docstring) -- comments are stripped from the whole file first (so a
    per-element trailing comment like `0, /* EMACIO0 */` does not need
    special-casing), then each `[...]  = {` is brace-balanced across lines and
    split on commas.
    """
    txt = open(path, encoding="utf-8", errors="replace").read()
    txt = re.sub(r"/\*.*?\*/", "", txt, flags=re.S)
    txt = re.sub(r"//[^\n]*", "", txt)
    arrays = {}
    lines = txt.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if "[" in line and "=" in line and re.search(r"\[\s*\]\s*=", line):
            m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*\]\s*=", line)
            if m:
                name = m.group(1)
                body = line[line.index("=") + 1:]
                depth = body.count("{") - body.count("}")
                while depth > 0 or "{" not in body:
                    i += 1
                    if i >= len(lines):
                        break
                    body += "\n" + lines[i]
                    depth = body.count("{") - body.count("}")
                inner = body[body.index("{") + 1: body.rindex("}")]
                words = [w.strip() for w in inner.replace("\n", " ").split(",") if w.strip()]
                arrays[name] = words
        i += 1
    return arrays


def load_arrays(qts_dir):
    """Merge the array definitions of every *.h directly inside qts_dir."""
    merged = {}
    headers = sorted(glob.glob(os.path.join(qts_dir, "*.h")))
    if not headers:
        raise LookupError("no *.h files found directly inside %r" % (qts_dir,))
    for h in headers:
        merged.update(parse_arrays(h))
    return merged


def pack_table(words, kind):
    vals = [int(w, 0) for w in words]
    if kind == "u8":
        return bytes(v & 0xFF for v in vals)
    if kind == "u32":
        return b"".join(struct.pack("<I", v & 0xFFFFFFFF) for v in vals)
    raise ValueError("unknown element type %r" % (kind,))


def pack_tables(qts_dir):
    """-> {name: (packed_bytes, n_elements)} for all of TABLES.

    Raises LookupError naming any table not DEFINED anywhere under qts_dir --
    that is a usage/input error (exit 2), distinct from a table that parses
    fine but is simply absent from an image's bytes (exit 1).
    """
    arrays = load_arrays(qts_dir)
    missing_defs = [name for name, _kind in TABLES if name not in arrays]
    if missing_defs:
        raise LookupError(
            "not defined in any *.h under %r: %s" % (qts_dir, ", ".join(missing_defs))
        )
    packed = {}
    for name, kind in TABLES:
        words = arrays[name]
        packed[name] = (pack_table(words, kind), len(words))
    return packed


def spl_copy0(image_path):
    with open(image_path, "rb") as f:
        data = f.read(SPL_COPY_SIZE)
    if len(data) < SPL_COPY_SIZE:
        raise LookupError(
            "%r is only %d bytes, shorter than one SPL copy (0x%x)"
            % (image_path, len(data), SPL_COPY_SIZE)
        )
    return data


def main(argv):
    prog = "qts-tables.py"
    if len(argv) < 3:
        sys.stderr.write(
            "usage: %s <qts-dir> <image> [<image> ...]\n" % (prog,)
        )
        return 2

    qts_dir, images = argv[1], argv[2:]

    if not os.path.isdir(qts_dir):
        sys.stderr.write("%s: no such directory: %s\n" % (prog, qts_dir))
        return 2

    try:
        packed = pack_tables(qts_dir)
    except (LookupError, ValueError, OSError) as e:
        sys.stderr.write("%s: %s\n" % (prog, e))
        return 2
    except SyntaxError as e:
        sys.stderr.write("%s: parse error: %s\n" % (prog, e))
        return 2

    copies = {}
    for image in images:
        if not os.path.isfile(image):
            sys.stderr.write("%s: no such file: %s\n" % (prog, image))
            return 2
        try:
            copies[image] = spl_copy0(image)
        except LookupError as e:
            sys.stderr.write("%s: %s\n" % (prog, e))
            return 2

    missing = 0
    for name, _kind in TABLES:
        blob, n_elements = packed[name]
        for image in images:
            offset = copies[image].find(blob)
            if offset >= 0:
                print(
                    "%s\t%s\tFOUND\t0x%05x\t%d\t%d"
                    % (name, image, offset, len(blob), n_elements)
                )
            else:
                missing += 1
                print(
                    "%s\t%s\tMISSING\t-\t%d\t%d"
                    % (name, image, len(blob), n_elements)
                )

    print(
        "SUMMARY\ttables=%d\timages=%d\tmissing=%d"
        % (len(TABLES), len(images), missing)
    )

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
