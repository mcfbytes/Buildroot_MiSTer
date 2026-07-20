# Upstream-only kernel patches

Patches carried **for the exported Linux-Kernel_MiSTer tree only**. Buildroot never
applies anything in this directory, so nothing here reaches the MiSTer image this repo
builds.

## Why this directory exists at all

`board/mister/de10nano/linux-patches/` is the series `BR2_LINUX_KERNEL_PATCH` points at.
Buildroot applies it, `scripts/export-kernel-tree.sh` replays it, and for most of this
repo's life those were the only kernel patches there were: the exported tree *was* the
kernel the image ships, patch for patch.

That stopped being possible once we started publishing the export upstream.
`MiSTer-devel/Linux-Kernel_MiSTer` is the kernel for **every** MiSTer, not just the one
this repo builds, and some of what it must carry our image specifically does not want.

The motivating case is the `loop=` boot parameter (fork commit `3d95de58f`, "Support for
init loop device."). It patches `init/do_mounts.c` so the kernel itself mounts
`/media/fat` and loop-mounts `linux/linux.img` as the root filesystem. That is how every
stock MiSTer boots — a 6.18 branch without it would not boot on any of them. Our image
replaced it with a real initramfs `/init` (recorded as carried-upstream-only in
`docs/kernel-recon/reconciliation.md` — carried for this tree, not for our image), so
applying it to our kernel would add a second,
unreachable boot path to something we ship.

Neither "delete it from the export" nor "apply it to the image" is acceptable: the first
breaks upstream's boot to preserve a tidy claim about our own tree, the second puts dead
code in a shipped kernel. So there are two series, and the divergence is written down —
in this file, in the export script, and in a table in the generated `EXPORT.md` — rather
than left to be rediscovered as drift.

## What belongs here

A patch belongs here when **all** of these hold:

- the exported tree needs it, because upstream MiSTer hardware or upstream's own boot
  flow depends on it;
- the MiSTer image this repo builds does **not** need it, and there is a specific reason
  why — usually that we solved the same problem a different way;
- shipping it in our image would be actively wrong, not merely unnecessary. "Harmless
  extra patch" is not a reason to split the series; it is a reason to carry it in
  `linux-patches/` like everything else and keep the two trees identical.

## What must never go here

**Anything the MiSTer image actually needs.** A patch in this directory is invisible to
every build, every CI run and every boot test in this repo. Put an image-critical fix
here and it will not be in the image, the build will stay green, and nothing will say so
until a device misbehaves in the field.

If in doubt, it goes in `linux-patches/`. That directory is the default; this one needs a
justification.

## Rules

**Numbering starts at 0100.** The carried series runs `0001`–`00xx`, so a four-digit
number beginning with `01` says which namespace a file is in without opening it or
checking which directory it came from — which matters when patches are quoted by
filename in review, in commit messages and in the recon docs.

**Every patch must state why it is not in the image.** The export publishes a table in
`EXPORT.md` naming each patch here and the reason our image does not apply it, and
`scripts/export-kernel-tree.sh` **fails closed** if it cannot find one. A table row with
a blank reason has the shape of a reviewed decision without being one, which is worse
than no table at all. Two ways to supply it, in the order the export looks:

1. a `Not-in-image: <one-line reason>` line in the patch's own commit message —
   preferred, because it survives rebases and re-exports with the patch;
2. a row in the `not-in-image` file next to this README, keyed by patch filename — for
   patches imported **verbatim** from the fork, where editing the message would mean
   rewriting someone else's commit text to satisfy a tool of ours.

**Patch format is identical to `linux-patches/`.** Full `git format-patch` mail headers
(`From:` with `Name <email>`, `Date:`, `Subject:`) and a `Provenance` section citing the
origin commit, its author, upstream status and the forward-port. `git am` hard-fails the
whole series on a malformed `From:`, and unlike the carried series nothing else in this
repo ever reads these files, so a defect here surfaces only at export time.

## Checks that gate this directory

    # mail headers are `git am`-able — lints this series and the carried one.
    # CI runs exactly this, with no arguments, before the image build.
    scripts/lint-kernel-patches.sh

    # this series alone
    scripts/lint-kernel-patches.sh board/mister/de10nano/linux-patches-upstream

    # full export: applies both series, checks every patch here produced a commit,
    # and refuses to write EXPORT.md if any of them has no stated reason
    scripts/export-kernel-tree.sh --output /tmp/kexport

    # what the tree looks like WITHOUT this series — i.e. exactly the shipped kernel.
    # Useful when diffing the export against a Buildroot build, where these patches
    # would otherwise be the only difference and make the comparison useless.
    scripts/export-kernel-tree.sh --output /tmp/kexport-shipped --no-upstream-patches

An empty or absent version of this directory is a valid state and all of the above
handle it: it simply means there are no upstream-only patches, and `EXPORT.md` then says
the exported tree is the shipped kernel.
