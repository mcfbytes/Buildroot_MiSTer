#!/usr/bin/env python3
"""Report which library each of an ELF binary's versioned undefined symbols comes from.

Written for P0.5 (docs/abi-contract.md §1.3) and consumed by P2.2 (scripts/check-abi.sh).

`readelf -d` tells you which libraries a binary NEEDs. It does not tell you *which symbols*
it needs from each, nor at which symbol version. That distinction is load-bearing here:
since glibc 2.34, libpthread/librt/libdl are version-placeholder stubs and the functions
themselves live in libc.so.6 as compat symbols at their historical versions. So the real
question a SONAME check must answer is not "does libpthread.so.0 exist" but:

    * does libpthread.so.0 still define the version node the binary asks for, and
    * does libc.so.6 still export those symbols at that version?

This script prints exactly the list you need to answer that.

Usage:
    scripts/abi/needed-symbols.py work/extracted/files/MiSTer
    scripts/abi/needed-symbols.py --symbols work/extracted/files/MiSTer   # every symbol

Output: one row per (library, version), sorted:

    libpthread.so.0    GLIBC_2.4        3  pthread_attr_setaffinity_np, pthread_create, ...
    librt.so.1         GLIBC_2.4        2  shm_open, shm_unlink

Requires `readelf` (binutils) on PATH. Works on any target architecture.
Exits 2 if readelf fails or the binary has no version-requirements section.
"""

import argparse
import collections
import re
import subprocess
import sys

# "  0x0010:   Name: GLIBC_2.4  Flags: none  Version: 2"  -- and the first row of each
# entry sometimes lacks the "0x" prefix ("  000000: Version: 1  File: libc.so.6  Cnt: 5").
RE_VERNEED_FILE = re.compile(r"^\s+(?:0x)?[0-9a-f]+:\s*Version:\s*\d+\s+File:\s*(\S+)\s+Cnt:")
RE_VERNEED_NAME = re.compile(r"^\s+(?:0x)?[0-9a-f]+:\s*Name:\s*(\S+)\s+Flags:\s*\S+\s+Version:\s*(\d+)")
# "   366: 00000000 0 FUNC GLOBAL DEFAULT UND pthread_create@GLIBC_2.4 (4)"
RE_UND_SYM = re.compile(r"\sUND\s+(\S+)@(\S+)\s+\((\d+)\)\s*$")


def collect(path):
    try:
        out = subprocess.run(
            ["readelf", "-W", "--dyn-syms", "--version-info", path],
            capture_output=True, text=True, check=True,
        ).stdout
    except FileNotFoundError:
        sys.exit("error: readelf not found on PATH (install binutils)")
    except subprocess.CalledProcessError as exc:
        sys.exit(f"error: readelf failed on {path}: {exc.stderr.strip()}")

    # version-requirement index -> (needed library, version node)
    by_index = {}
    current_file = None
    for line in out.splitlines():
        match = RE_VERNEED_FILE.match(line)
        if match:
            current_file = match.group(1)
            continue
        match = RE_VERNEED_NAME.match(line)
        if match and current_file:
            by_index[int(match.group(2))] = (current_file, match.group(1))

    if not by_index:
        sys.exit(f"error: {path} has no .gnu.version_r section (not dynamically linked?)")

    needed = collections.defaultdict(set)
    for line in out.splitlines():
        match = RE_UND_SYM.search(line)
        if match:
            symbol, version, index = match.group(1), match.group(2), int(match.group(3))
            needed[by_index.get(index, ("?", version))].add(symbol)
    return needed


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("binary", help="path to a dynamically-linked ELF")
    parser.add_argument("--symbols", action="store_true",
                        help="print every symbol, not just the first six")
    args = parser.parse_args()

    needed = collect(args.binary)
    for library, version in sorted(needed):
        symbols = sorted(needed[(library, version)])
        shown = symbols if args.symbols else symbols[:6]
        suffix = "" if len(shown) == len(symbols) else ", ..."
        print("%-18s %-14s %3d  %s%s"
              % (library, version, len(symbols), ", ".join(shown), suffix))


if __name__ == "__main__":
    main()
