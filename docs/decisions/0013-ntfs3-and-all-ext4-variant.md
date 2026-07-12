# ADR 0013 — Add `ntfs3`; park the all-ext4 image variant (answers Q4)

**Status:** Accepted (2026-07-12) — decided by @mcfbytes
**Supersedes:** `docs/phase0-review.md` Q4
**Impact:** P2.1 (package set), P2.7 (size budget), P1.11 (zImage budget)

## Decision

1. **Add `ntfs3`** — but build it as a **module**, and leave it **disabled by
   default until stock parity has been demonstrated.**
2. **Park the all-ext4 image variant** as a future opt-in. Do not build it now.

## Rationale and consequences — `ntfs3`

Stock has no NTFS support at all, so this is a pure addition and cannot regress
parity by itself. Two constraints:

- **Module, not built-in.** Anything built into the kernel lands in `zImage_dtb`,
  which P1.11 must assert against the U-Boot size budget. NTFS is not needed to
  boot.
- **Default off until parity is proven.** The project's whole thesis is
  *prove parity, then improve.* Every feature enabled before parity is
  demonstrated confounds the two questions we most need to keep apart: "did we
  break something stock did?" versus "did something we added break?" Flip it on
  once P2 parity passes.

Worth noting for the eventual user docs: `ntfs3` read/write on a device that users
routinely power off by **pulling the plug** is a corruption risk. Mounting NTFS
read-only by default is the conservative call.

## Rationale and consequences — all-ext4 variant

**More technically feasible than expected.** U-Boot uses the *generic* `load`
command, not `fatload`:

```
mmcload = mmc rescan; run fpgacheck; run scrtest;
          load mmc 0:$mmc_boot $loadaddr $bootimage; ...
```

(`docs/boot-chain.md:255-260`.) Generic `load` autodetects the filesystem, so it
can read `zImage_dtb` from ext4 provided U-Boot is built with ext4 support. And
under the §5 design we author the initramfs mount anyway (see ADR 0010(c)), so the
root side is ours to change. The `0xA2` U-Boot partition is raw and unaffected.

The real blockers are **ecosystem, not technical**:

- **The card stops being readable on Windows/macOS.** Accepted premise of the
  feature — content arrives over the network instead.
- **Permissions become real.** exFAT synthesises `0755` for everything via
  `fmask=0022,dmask=0022`. On ext4, permissions and the exec bit are *stored*.
  MiSTer scripts and cores copied in from a PC can land without `+x`, and things
  that "just worked" on exFAT start failing in ways that look like our bug. This
  is the subtle breakage class that will eat the time budget, not the boot path.
- **Possibly a one-way door.** Whether the *stock* image can still boot an ext4
  p1 is untested (its `do_mounts` patch autodetects the filesystem and ext4 is
  built in, so it might — but this is unverified and must not be assumed). Until
  someone proves it, treat "reformat to ext4" as **not rollback-able to stock.**
- Journalled writes increase write amplification on cheap SD cards. Minor, but
  the motivation for the feature was exFAT's lack of a journal, so it is worth
  being honest that ext4's journal is not free either.

Ship it, if we ship it, as a clearly-labelled **separate image variant** — never as
a change to the default image.
