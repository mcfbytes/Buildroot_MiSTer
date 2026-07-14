# User documentation

Docs for people running (or considering running) this project's Linux image on real
MiSTer hardware. **This is a personal-use project** until the sustainability sign-off in
[ADR 0014](../decisions/0014-sustainability-deferred-not-waived.md) — start with
[`beta-testing.md`](beta-testing.md) if you haven't already, so the posture you're opting
into is clear.

| Doc | Read this when... |
|---|---|
| [`onboarding.md`](onboarding.md) | You want to start receiving updates for this image via the Downloader. Covers the exact file to add and the multi-database ordering rule that decides whether it's a one-line change or a support thread. |
| [`rollback.md`](rollback.md) | You want back to the stock image, for any reason. Calm, short, and safe at any time. |
| [`serial-recovery.md`](serial-recovery.md) | Your box isn't booting after an update and you need to see what's actually happening, or recover it. |
| [`faq.md`](faq.md) | Default credentials, SSH host keys, what changed vs. stock, how updates work, how to report a bug. |
| [`beta-testing.md`](beta-testing.md) | The overall personal-use/beta posture, hardware-validation status, and how issue reporting fits together. |

Technical readers wanting the underlying, source-cited contracts these docs summarize:
[`../downloader-contract.md`](../downloader-contract.md) (the Downloader/`db.json`
mechanism), [`../boot-chain.md`](../boot-chain.md) (the boot sequence), and
[`../abi-contract.md`](../abi-contract.md) (what this image must not break).
