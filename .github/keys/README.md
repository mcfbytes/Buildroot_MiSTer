# Checked-in PGP trust roots

Public keys used by `.github/workflows/renovate-hash-sync.yml` to verify
kernel.org artifacts before writing
`board/mister/de10nano/patches/linux/linux.hash`.

**These are committed on purpose.** A key fetched from the network at the moment
of use is not a trust root — it is just another thing an attacker can serve you.
Pinning them here makes each key an ordinary reviewable, diffable file, and makes
rotating or adding one a normal PR with a human in the loop.

Rationale, threat model, and the honest weaknesses:
[ADR 0021](../../docs/decisions/0021-kernel-hash-gpg-verification.md).

| File | Key | Fingerprint | Provenance |
|---|---|---|---|
| `kernel.org-gregkh.asc` | Greg Kroah-Hartman (Linux kernel stable release signing key) | `647F2865 4894E3BD 457199BE 38DBBDC8 6092693E` | **Cross-checked** against <https://www.kernel.org/signature.html> |
| `kernel.org-autosigner.asc` | Kernel.org checksum autosigner `<autosigner@kernel.org>` | `B8868C80 BA62A1FF FAF5FDA9 632D3A06 589DA6B1` | **TOFU** — see caveat below |

Both were exported with `--export-options export-minimal` (no third-party
signatures), so the files stay small and reviewable.

## Caveat on the autosigner key

kernel.org publishes neither this key nor its fingerprint anywhere findable:
`signature.html` describes the autosigner system but lists no fingerprint, there
is no `autosigner.asc` under `/pub/linux/kernel/`, and keys.openpgp.org returns
404 for it. It was obtainable only from `keyserver.ubuntu.com`, which accepts
unverified uploads.

So trust in it is **trust-on-first-use**. Pinning it still buys something real —
it detects any future change of signer or manifest provenance — but it is not an
independently-rooted anchor, which is exactly why the workflow also verifies the
maintainer signature on the tarball itself and requires the two to agree.

## Verifying these files yourself

```sh
gpg --show-keys --with-fingerprint .github/keys/kernel.org-gregkh.asc
gpg --show-keys --with-fingerprint .github/keys/kernel.org-autosigner.asc
```

Compare the first against kernel.org's published fingerprint. The second cannot
be cross-checked against kernel.org; the best available check is that it is the
key which has signed the `sha256sums.asc` files this project has been consuming.

## Adding a signer

Some stable releases are signed by a different maintainer (e.g. Sasha Levin). If
the kernel line moves to one, the workflow fails **closed** with a message
saying so. Export that key here, check its fingerprint against
`kernel.org/signature.html`, add it to the import list and the fingerprint
allow-list in the workflow, and note it in ADR 0021. A new signer is a trust
decision a human should be making deliberately.
