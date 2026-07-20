# ADR 0022 — Verify the kernel tarball hash under two checked-in PGP keys

**Status:** Accepted (2026-07-18) — decided by @mcfbytes
**Impact:** `.github/workflows/renovate-hash-sync.yml`, `.github/keys/*.asc`,
`board/mister/de10nano/patches/linux/linux.hash`

## 1. The gap

`renovate-hash-sync.yml` refreshes `linux.hash` when Renovate bumps
`BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`. It did so by fetching kernel.org's
`sha256sums.asc` over HTTPS and grepping the matching line.

That file is PGP-clearsigned, but **the signature was never checked**. The
`.asc` extension was doing no work: we would have got the identical result from
a plain text file. Trust rested entirely on TLS plus the CDN, and GitHub's
Ubuntu runners ship no kernel.org keyring, so nothing on the box could have
checked it even incidentally.

The consequence is narrow but real. Anything able to serve us a manifest — a
compromised mirror, a mis-issued certificate, or (as actually happened, see §5)
a bug in our own URL construction — could hand us a hash that we would commit to
`linux.hash`. Buildroot would then dutifully "verify" the downloaded tarball
against it and pass. The hash file would be **self-consistently wrong**: every
check green, contents attacker-chosen.

## 2. Why `linux.hash` cannot simply be replaced by a signature check

A reasonable first instinct is to drop the stored hash and verify a signature at
build time instead. That does not apply here:

* `linux.hash` is **Buildroot's own file format**, consumed by Buildroot's
  download infrastructure. Buildroot has no PGP support to defer to; the hash
  file *is* its integrity mechanism.
* The stored hash is also the **human-reviewable artifact**. A kernel bump PR
  shows the hash changing in the diff, which is what makes the bump auditable.

So GPG verification is not an alternative to the hash file. It is the missing
provenance layer for **how the value gets into it**. The hash stays; what
changes is that it can now only be written from signed input.

## 3. Decision

Derive the hash under **two independent signatures**, both verified against
public keys **committed under `.github/keys/`**. Keys are never fetched at run
time — a key pulled from the network at the moment of use is not a trust root,
it is just another thing the attacker serves you.

| | path A | path B |
|---|---|---|
| artifact | `linux-<ver>.tar.sign` | `sha256sums.asc` |
| signer | Greg Kroah-Hartman (stable maintainer) | kernel.org checksum autosigner |
| fingerprint | `647F2865 4894E3BD 457199BE 38DBBDC8 6092693E` | `B8868C80 BA62A1FF FAF5FDA9 632D3A06 589DA6B1` |
| covers | the uncompressed `.tar` | a checksum manifest for the whole series |
| hash obtained by | `sha256sum` of the verified `.tar.xz` | parsing gpg's verified plaintext |

Both must verify **and agree on the hash**, or the step fails hard and refuses
to touch `linux.hash`.

Three details that are load-bearing rather than incidental:

1. **Path A ties the signature to the exact file we downloaded.** The `.sign`
   covers the *uncompressed* tar, but Buildroot hashes the `.tar.xz`. We
   decompress the `.tar.xz` we actually fetched and verify *that stream*; a
   tampered `.xz` cannot decompress to signed content. Only then do we hash the
   `.xz`.
2. **Path B parses only gpg's output**, never the raw `.asc`. Grepping the
   signed file directly would make the verification decorative — the classic way
   this control is implemented and defeated at the same time.
3. **Verification is pinned by fingerprint** via the `VALIDSIG` line on gpg's
   `--status-fd` channel. gpg's exit status is too weak a gate (it can be 0 for
   a good-but-expired key) and its human-readable output is influenceable
   through filenames. Confirmed by test: a *valid* signature from the wrong
   checked-in key is rejected.

A signature failure is a supply-chain event, not a transient one, so it is never
downgraded to the warn-and-skip path used for network errors.

## 4. Why these two keys, and an honest note on the autosigner

The two keys are **not** of equal trustworthiness, and it is worth recording why
both are here anyway.

**The maintainer key is cross-checkable.** Its fingerprint is published on
<https://www.kernel.org/signature.html>, so the key committed here can be
verified against an authoritative kernel.org document rather than taken on
faith. kernel.org also states plainly that developer signatures are the "best
assurance".

**The autosigner key is TOFU-pinned, and that is a real weakness.** kernel.org
publishes neither that key nor its fingerprint anywhere findable (`signature.html`
describes the autosigner system but lists no fingerprint; there is no
`autosigner.asc` under `/pub/linux/kernel/`; keys.openpgp.org 404s it). It was
obtainable only from `keyserver.ubuntu.com`, which accepts unverified uploads.
So the *initial* trust in it is trust-on-first-use.

Committing it is still worth doing: once pinned, it detects any future change of
signer or manifest provenance, which is exactly what an unverified fetch cannot
do. But it should not be mistaken for an independently-rooted trust anchor, and
it is the reason path A exists rather than path B alone. This repo already
carries a documented TOFU pin for the same class of reason (the 7.2-rc kernel,
which has no signed manifest at all).

kernel.org itself is explicit that the checksums are a mirror-consistency
mechanism and "NOT intended to replace developer signatures" — so path B is
corroboration, not the foundation.

**Rejected — autosigner only:** cheaper (no tarball download) but rests entirely
on the TOFU key, and on the artifact kernel.org tells you not to rely on.

**Rejected — maintainer only:** defensible, and nearly what we do. Adding path B
costs one small download and catches disagreement between two separate kernel.org
systems, which neither path detects alone.

## 5. Cost

~19 s per kernel bump, almost all of it the 147 MB tarball download (~1.3 s on
the CDN; decompress-and-verify ~2 s). Kernel bumps are monthly at most. The
cost objection that motivated the original "no keyring management here yet"
shortcut turned out not to exist.

## 6. Consequences

* A kernel bump PR now fails **loudly and unmergeably** if either signature
  fails or the two disagree, instead of silently writing an unverified hash.
* Adding a kernel line signed by a different maintainer (e.g. Sasha Levin signs
  some stable releases) requires committing that key under `.github/keys/` after
  checking its fingerprint against `kernel.org/signature.html`. Until then the
  step fails closed with a message saying exactly that. This is intended: a new
  signer is a trust decision a human should make.
* The keys are ordinary reviewable files in git. Rotating or adding one is a
  normal, diffable PR.
* This does **not** extend to `BUILDROOT_SHA256`, which remains a deliberate
  manual transcription from Buildroot's signed manifest (see the root Makefile's
  header and `docs/renovate.md`).
