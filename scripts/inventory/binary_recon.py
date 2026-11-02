#!/usr/bin/env python3
"""Per-path binary reconciliation: stock image vs. a Buildroot_MiSTer rootfs.

Enumerates the executable surface of both trees (every file/symlink under
usr/bin, usr/sbin, usr/libexec, libexec, plus every ELF executable and every
executable script anywhere outside etc/),
attributes each path to a package and version, and writes one TSV row per path.

Attribution:
  ours  -- output/build/packages-file-list.txt (path -> package) and
           `make show-info` (package -> version). Exact.
  stock -- stock has no package list. A path resolving to busybox is BusyBox;
           otherwise the package that installs the same path (or, failing that,
           the same basename) in ours is the candidate, versioned from the
           stock Buildroot's package/*.mk (stock is Buildroot 2021.02.4).
           --stock-overrides (TSV: path<TAB>package<TAB>version<TAB>evidence)
           replaces the candidate where the image itself proves otherwise.

Usage:
  binary_recon.py --stock ROOT --ours ROOT --pkg-list packages-file-list.txt \
      --show-info show-info.json --stock-versions br-versions.json \
      [--stock-overrides overrides.tsv] [--ours-overrides overrides.tsv] \
      [--pairs pairs.tsv] [--stock-prefix-attr prefixes.tsv] \
      [--ours-overlay DIR] > recon.tsv

Data-only: never executes anything from either tree.
"""
import argparse, json, os, struct, sys

EXEC_DIRS = ("usr/bin", "usr/sbin", "usr/libexec", "libexec", "bin", "sbin")
SKIP_TOP = {"proc", "sys", "dev", "run", "tmp", "lost+found"}


def rel_resolve(root, rel, depth=0):
    """Resolve rel (root-relative) through symlinks, staying inside root."""
    parts = [p for p in rel.split("/") if p]
    out = []
    for i, p in enumerate(parts):
        if p == "..":
            if out:
                out.pop()
            continue
        if p == ".":
            continue
        cand = "/".join(out + [p])
        full = os.path.join(root, cand)
        if os.path.islink(full) and depth < 40:
            tgt = os.readlink(full)
            base = "" if tgt.startswith("/") else "/".join(out)
            rest = "/".join(parts[i + 1:])
            joined = "/".join(x for x in (base, tgt.lstrip("/"), rest) if x)
            return rel_resolve(root, joined, depth + 1)
        out.append(p)
    return "/".join(out)


def elf_kind(path):
    try:
        with open(path, "rb") as f:
            h = f.read(52)
            if len(h) < 52 or h[:4] != b"\x7fELF":
                return None
            if h[4] != 1:  # ELFCLASS64 -- treat generically
                return "elf"
            e_type, = struct.unpack_from("<H", h, 16)
            if e_type == 2:
                return "elf-exec"
            if e_type != 3:
                return "elf-other"
            phoff, = struct.unpack_from("<I", h, 28)
            phentsize, phnum = struct.unpack_from("<HH", h, 42)
            f.seek(phoff)
            ph = f.read(phentsize * phnum)
            for i in range(phnum):
                p_type, = struct.unpack_from("<I", ph, i * phentsize)
                if p_type == 3:  # PT_INTERP
                    return "elf-pie"
            return "elf-lib"
    except OSError:
        return None


def file_kind(path):
    if os.path.islink(path):
        return "symlink"
    if not os.path.isfile(path):
        return "other"
    k = elf_kind(path)
    if k:
        return k
    try:
        with open(path, "rb") as f:
            if f.read(2) == b"#!":
                return "script"
    except OSError:
        pass
    return "exec-data" if os.access(path, os.X_OK) else "data"


def enumerate_tree(root):
    paths = set()
    for d in EXEC_DIRS:
        top = os.path.join(root, d)
        if os.path.islink(top) or not os.path.isdir(top):
            continue
        for dp, dns, fns in os.walk(top):
            for n in fns + [x for x in dns if os.path.islink(os.path.join(dp, x))]:
                paths.add(os.path.relpath(os.path.join(dp, n), root))
    for dp, dns, fns in os.walk(root):
        rel = os.path.relpath(dp, root)
        if rel == ".":
            dns[:] = [x for x in dns if x not in SKIP_TOP]
        for n in fns:
            full = os.path.join(dp, n)
            if os.path.islink(full):
                continue
            if elf_kind(full) in ("elf-exec", "elf-pie"):
                paths.add(os.path.relpath(full, root))
            elif (rel.split("/")[0] != "etc" and os.access(full, os.X_OK)
                  and file_kind(full) == "script"):
                paths.add(os.path.relpath(full, root))
    if os.path.lexists(os.path.join(root, "linuxrc")):
        paths.add("linuxrc")
    return paths


def describe(root, rel):
    full = os.path.join(root, rel)
    kind = file_kind(full)
    link = os.readlink(full) if kind == "symlink" else ""
    final = rel_resolve(root, rel)
    fk = file_kind(os.path.join(root, final)) if os.path.lexists(os.path.join(root, final)) else "dangling"
    size = os.path.getsize(os.path.join(root, final)) if fk not in ("dangling", "other") else ""
    return kind, link, final, fk, size


def load_overrides(path):
    o = {}
    if path:
        for line in open(path):
            if not line.strip() or line.startswith("#"):
                continue
            f = line.rstrip("\n").split("\t")
            o[f[0]] = (f[1], f[2], f[3] if len(f) > 3 else "")
    return o


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stock", required=True)
    ap.add_argument("--ours", required=True)
    ap.add_argument("--pkg-list", required=True)
    ap.add_argument("--show-info", required=True)
    ap.add_argument("--stock-versions", required=True)
    ap.add_argument("--stock-overrides")
    ap.add_argument("--ours-overrides")
    ap.add_argument("--pairs", help="TSV: stock_path<TAB>ours_path<TAB>note -- "
                    "the same file under a renamed/relocated path")
    ap.add_argument("--stock-prefix-attr", help="TSV: path_prefix<TAB>package; "
                    "fallback stock attribution for paths under a prefix")
    ap.add_argument("--ours-overlay", action="append", default=[],
                    help="BR2_ROOTFS_OVERLAY dir(s); unowned paths found there "
                         "are attributed to the overlay")
    a = ap.parse_args()

    owner, base_owner = {}, {}
    for line in open(a.pkg_list):
        pkg, _, p = line.rstrip("\n").partition(",")
        p = p[2:] if p.startswith("./") else p
        owner[p] = pkg  # last writer wins, as on the target
    for p, pkg in owner.items():
        base_owner.setdefault(os.path.basename(p), set()).add(pkg)
    txt = open(a.show_info).read()
    info = json.loads(txt[txt.index("{"):])
    ours_ver = {k: v.get("version", "") for k, v in info.items()}
    # linux-tools (perf, ...) builds from the kernel tree and has no version of its own
    ours_ver.setdefault("linux-tools", "")
    ours_ver["linux-tools"] = ours_ver["linux-tools"] or ours_ver.get("linux", "")
    stock_ver = json.load(open(a.stock_versions))
    so, oo = load_overrides(a.stock_overrides), load_overrides(a.ours_overrides)
    pairs = {}
    for line in open(a.pairs) if a.pairs else []:
        if line.strip() and not line.startswith("#"):
            sp, op, note = (line.rstrip("\n").split("\t") + [""])[:3]
            pairs[sp.lstrip("/")] = ("/" + op.lstrip("/"), "stock", note)
            pairs[op.lstrip("/")] = ("/" + sp.lstrip("/"), "ours", note)
    prefixes = []
    for line in open(a.stock_prefix_attr) if a.stock_prefix_attr else []:
        if line.strip() and not line.startswith("#"):
            prefixes.append(tuple(line.rstrip("\n").split("\t")[:2]))

    def norm(root, p):
        # bin -> usr/bin, sbin -> usr/sbin on merged-usr trees
        for d in ("bin", "sbin"):
            if p.startswith(d + "/") and os.path.islink(os.path.join(root, d)):
                return "usr/" + p
        return p

    S = {norm(a.stock, p) for p in enumerate_tree(a.stock)}
    O = {norm(a.ours, p) for p in enumerate_tree(a.ours)}

    def ours_attr(p, final):
        if p in oo:
            return oo[p][0], oo[p][1], "override: " + oo[p][2]
        if final.endswith("busybox"):
            return "busybox", ours_ver.get("busybox", ""), "symlink->busybox"
        pkg = owner.get(p) or owner.get(final)
        how = "packages-file-list"
        if not pkg:
            c = base_owner.get(os.path.basename(p), set())
            pkg = sorted(c)[0] if len(c) == 1 else ""
            how = "basename" if pkg else "unattributed"
        if not pkg:
            for ov in a.ours_overlay:
                if os.path.lexists(os.path.join(ov, p)):
                    return "rootfs-overlay", "(this repo)", "overlay: " + ov
        return pkg, ours_ver.get(pkg, ""), how

    def stock_attr(p, final):
        if p in so:
            return so[p][0], so[p][1], "override: " + so[p][2]
        if final.endswith("busybox"):
            return "busybox", stock_ver.get("busybox", ""), "symlink->busybox"
        pkg = owner.get(p) or owner.get(final)
        how = "same-path-in-ours"
        if not pkg or pkg == "busybox":
            c = base_owner.get(os.path.basename(p), set()) - {"busybox"}
            pkg = sorted(c)[0] if len(c) == 1 else ""
            how = "basename-in-ours" if pkg else "unattributed"
        if not pkg:
            for pre, ppkg in prefixes:
                if p.startswith(pre.lstrip("/")):
                    pkg, how = ppkg, "path-prefix " + pre
                    break
        sv = stock_ver.get(pkg, "")
        return pkg, sv, how

    cols = ["path", "status", "stock_kind", "stock_target", "stock_package",
            "stock_version", "stock_attribution", "ours_kind", "ours_target",
            "ours_package", "ours_version", "ours_attribution", "counterpart"]
    print("\t".join(cols))
    for p in sorted(S | O):
        row = {"path": "/" + p}
        for side, root, present, attr in (("stock", a.stock, p in S, stock_attr),
                                          ("ours", a.ours, p in O, ours_attr)):
            if not present:
                row.update({side + "_kind": "absent", side + "_target": "",
                            side + "_package": "", side + "_version": "",
                            side + "_attribution": ""})
                continue
            kind, link, final, fk, size = describe(root, p)
            pkg, ver, how = attr(p, final)
            row.update({side + "_kind": kind if kind != "symlink" else "symlink:" + fk,
                        side + "_target": link, side + "_package": pkg,
                        side + "_version": ver, side + "_attribution": how})
        row["counterpart"] = pairs[p][0] if p in pairs else ""
        sk, ok = row["stock_kind"], row["ours_kind"]
        sp, op = row["stock_package"], row["ours_package"]
        if p in pairs and (sk == "absent") != (ok == "absent"):
            st = "relocated-from" if sk == "absent" else "relocated-to"
        elif sk == "absent":
            st = "ours-only"
        elif ok == "absent":
            st = "stock-only"
        elif sp == "busybox" and op == "busybox":
            st = "both-busybox"
        elif sp == "busybox":
            st = "busybox->real"
        elif op == "busybox":
            st = "real->busybox"
        elif sp and op and sp != op:
            st = "provider-changed"
        else:
            st = "same-provider"
        row["status"] = st
        print("\t".join(str(row[c]) for c in cols))


if __name__ == "__main__":
    sys.exit(main())
