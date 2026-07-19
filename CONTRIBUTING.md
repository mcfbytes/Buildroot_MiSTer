# Contributing to MiSTer Linux Modernization

Thank you for your interest in contributing. This project is not yet accepting public contributions — Phase 4 is in progress and the sustainability gate (ADR 0014) must be signed before this is open. When it is open, please follow the discipline below.

---

## Developer Certificate of Origin

All contributions must be signed off with a Developer Certificate of Origin (DCO). This is a lightweight way to certify that you wrote the patch or have the right to contribute it.

**To sign off your commits:**

```sh
git commit -s   # Adds "Signed-off-by: Name <email>" to your commit message
```

By signing off, you agree to the terms of the [Developer Certificate of Origin (DCO), version 1.1](https://developercertificate.org/).

**All pull requests without `Signed-off-by` footers will be rejected.**

---

## Standing Rules (apply to every contribution)

These rules are load-bearing and non-negotiable. They protect reproducibility, maintainability, and the integrity of the project's core promise.

### 1. No binaries in git. Ever.

Binaries, pre-built artifacts, and large downloads belong in external storage.

- Reference materials (stock images, kernel tarballs) go in an untracked `work/` directory (listed in `.gitignore`).
- Release artifacts are published as GitHub Release assets, never committed into the repo.
- Firmware and external packages are fetched at build time with verified hashes, not vendored.

**Rationale:** Reproducible builds require pristine, auditable sources. Binaries cannot be audited and bloat the repository's history.

### 2. Every kernel patch must carry a provenance header.

There are **two** kernel patch directories, and picking the right one is the first
question to answer, not an afterthought:

- `board/mister/de10nano/linux-patches/` — the default. Applied to the image this repo
  builds *and* replayed into the tree `scripts/export-kernel-tree.sh` publishes upstream
  (PR #75 against `MiSTer-devel/Linux-Kernel_MiSTer`). If in doubt, your patch goes here.
- `board/mister/de10nano/linux-patches-upstream/` — for the rare patch that
  **upstream's** kernel needs but this repo's own image deliberately does not (see that
  directory's `README.md` for the exact criteria, and `docs/patch-provenance.md` §12 for
  the motivating example). Buildroot never applies anything here; only the export does.

Every file in either directory must include:

- **Origin commit SHA** (or GitHub issue/PR URL) from the upstream kernel or the stock MiSTer fork
- **Original author and copyright holder**
- **Upstream status:** Is this patch in mainline? If so, which version?
- **Disposition:** Why are we carrying this? (bug fix, new feature, ABI requirement, etc.)
- **`Signed-off-by`** footer (your sign-off, and any upstream sign-offs the patch carries)

**Example patch header:**

```
From: Sorgelig <sorgelig@example.com>
Date: Mon, 15 Aug 2021 12:34:56 +0000
Subject: fbdev: add MiSTer framebuffer device

Origin: Upstream commit d1002ecd4, MiSTer-devel/Linux-Kernel_MiSTer
Author: Sorgelig
Upstream status: Not merged (MiSTer-specific device)
Reason for carrying: Provides /dev/fb0 interface required by Main_MiSTer
(patch body follows)

Signed-off-by: Sorgelig <sorgelig@example.com>
Signed-off-by: Your Name <your@email.com>
```

**Updates to `docs/patch-provenance.md`** must be committed in the same PR that adds or modifies a patch.

**Rationale:** Kernel patch maintenance is the single largest maintenance burden in this project. Provenance tracking lets us:
- Identify patches that have moved upstream and can be dropped
- Recover the original author's intent if a patch needs rebasing
- Audit why we carry each patch and justify its cost
- Hand a patch back to upstream when the time comes

See `docs/patch-provenance.md` for the complete triage discipline and methodology.

### 3. Source pinning and hash verification

All external sources (kernel, Buildroot, packages, firmware) must be:

- **Pinned to a specific version** (tag, commit SHA, or release date — no floating refs)
- **Verified against a hash** (SHA-256 for tarballs, commit SHA for git)
- **Downloaded at build time**, not vendored
- **Documented** in the build file or top-level Makefile

**Examples:**

```makefile
# Bad: floating reference
KERNEL_VERSION = 6.18.y

# Good: pinned tag
KERNEL_VERSION = 6.18.38

# Bad: no hash
curl https://kernel.org/linux-6.18.38.tar.xz

# Good: hash-verified
curl -o linux-6.18.38.tar.xz https://kernel.org/linux-6.18.38.tar.xz
sha256sum -c <<< 'abc123...  linux-6.18.38.tar.xz'
```

**Rationale:** Reproducible builds require exact source material. Any floating reference or unverified download can produce a silently different output tomorrow.

### 4. Reproducible builds

Every task that changes build output must end with a successful build of the affected stage.

- If a change touches kernel config, run `make linux` and verify zero warnings (`W=1`).
- If a change touches a package, run `make` and verify the build succeeds.
- If the environment cannot run `make` (e.g., you're on an unsupported OS), document the reason in your commit message.

**Rationale:** We ship an image-based update. A silent build failure means users get the old image while thinking they have the new one.

### 5. Documentation lives with the code

Docs are updated in the same PR (or commit) as the code they describe.

- Changes to `TASKS.md` checklist: update it when you complete the task.
- Changes to kernel patches: update `docs/patch-provenance.md` at the same time.
- Changes to build mechanics: update relevant docs in `docs/` or the Makefile's inline help.
- New decision or trade-off: create an ADR in `docs/decisions/` (see existing ADRs for format).

**Rationale:** Separated docs rot. A PR is the checkpoint where we verify both code and documentation are accurate.

### 6. License clarity

- **Kernel patches** (`board/mister/de10nano/linux-patches/*.patch`): **GPLv2** (they modify the Linux kernel)
- **Buildroot external tree and scripts**: **GPLv3** (see `LICENSE`)
- **Packages** (`package/`): inherit upstream license (typically GPLv2, BSD, MIT, etc.)
- **New packages**: Verify the license is compatible and document it in the package's `.mk` file

If a package has a restrictive or unclear license, flag it in the commit message and PR.

**Rationale:** Compliance and community trust. We cannot silently ship incompatibly-licensed code.

### 7. Commit messages explain *why*

Commit messages must explain the rationale, not just the *what*.

**Bad:**
```
Update kernel config
- Add CONFIG_DEBUG_INFO=y
```

**Good:**
```
P2.5: Enable kernel debug info for crash-dump analysis

Add CONFIG_DEBUG_INFO=y to the kernel config so crash dumps
can be post-processed by tools like Oops analyzer. Increases
zImage by ~50 MB uncompressed (included in binary anyway via DWARF);
compressed size increase is negligible.

Signed-off-by: Your Name <your@email.com>
```

Also:
- **PR title:** Keep it short (< 70 characters). Reference the task ID (e.g., `P4.9: community & governance files`).
- **PR body:** Explain the *why*, link to related issues/PRs, and list any testing you've done.

**Rationale:** `git blame` is a maintenance tool. Future maintainers (including you in 6 months) need to understand not just *what* changed, but *why* it was necessary.

---

## Contribution Workflow

1. **Check the task list** (`TASKS.md`) — find an open task with a `- [ ]` checkbox.
2. **Discuss first** (for large changes) — open an issue or comment on the task to coordinate.
3. **Work in a branch** — create a feature branch off `master`.
4. **Test locally** — run `make` to verify the build succeeds (or document why it cannot).
5. **Commit with sign-off** — `git commit -s` with a clear message explaining *why*.
6. **Push and open a PR** — reference the task ID (`TASKS.md` P*.*) in the PR title.
7. **Respond to review** — we may ask for provenance details, test results, or documentation updates.

---

## What We're Looking For

Contributions should fit the project's scope and constraints:

- **In scope:** Kernel patches (with provenance), Buildroot package configs, CI/CD, documentation, and test infrastructure.
- **Out of scope:** Forking cores, changing the musl/Alpine, adding a package manager, or anything that breaks the ABI contract.

See `PLAN.md` for the full list of goals and non-goals.

---

## Questions?

- **Project context:** Start with `PLAN.md` and `TASKS.md`.
- **Patch discipline:** See `docs/patch-provenance.md` and existing patches in `board/mister/de10nano/linux-patches/`.
- **Technical details:** Check `docs/decisions/` for ADRs on specific trade-offs.
- **Sustainability model:** See `PLAN.md` §13 and ADR 0014.

Thank you for helping make MiSTer more sustainable.
