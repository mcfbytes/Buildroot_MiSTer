# ADR 0005 — Sustainability gate: deferred, **not waived** (answers Q5)

**Status:** Deferred (2026-07-12) — decided by @mcfbytes
**Supersedes:** `docs/phase0-review.md` Q5; TASKS.md §C; PLAN §13
**Impact:** **Blocks P4.10 (beta launch). Does not block Phase 0 → Phase 1.**

## Decision

Do not sign the maintainer commitment now. Proceed with Phase 1+ **for personal
use.** The gate stays open and must be revisited before any public release.

## The reframing this ADR exists to record

The decision was made on the basis that *"Claude is doing the heavy lifting."*
That is true of **authoring**, and it genuinely changes the labour estimate. It
does **not** change what TASKS.md §C is actually asking for, and the distinction
matters enough to write down:

- **No continuity.** Claude starts every session cold. It cannot watch 6.18.y,
  cannot notice a CVE, cannot be paged. Every single action requires a human to
  open a session and pay for it.
- **No hardware.** Verifying a stable bump means booting it on a DE10-Nano. No
  model can do that.
- **Automation is a mechanism, not an owner.** Renovate (P4.6/P4.7) opens PRs. A
  bot whose PRs nobody merges and nobody tests is a stale fork *with extra steps*.

What §C asks for is not labour. It is **accountability and continuity** — someone
who notices a fix landed, decides it matters, tests it on real hardware, and ships
it. That role is unfilled, and Claude structurally cannot fill it.

## Why deferring is nonetheless correct

PLAN §13's argument — *a stale fork is worse than no fork* — depends on a fork that
**displaces the maintained stock image and inherits its users.** For a single
person running an image on their own device, that argument does not apply at all:
no one else is exposed, and the failure mode is reversible by reflashing.

The risk only appears at publication. Hence: defer, don't waive.

## The condition, stated so it cannot be drifted past

> **Unsigned ⇒ personal use only.** Do not publish an image, a `db.json`, or a
> Downloader entry that other people's devices consume until a named human has
> committed in writing (in the README) to tracking 6.18.y through EOL (Dec 2028).

The failure mode this guards against is not a decision — it is **drift**: reaching
a working image, sharing it because it works, and never revisiting the gate.
P4.10 must re-read this ADR.

And the honest observation: if you are the only human on this project, then you
*are* the named maintainer by default. The open question is not who it would be —
it is whether you are willing to write it down **before** other people start
depending on it.
