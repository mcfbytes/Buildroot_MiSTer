# ADR 0018 — `/MiSTer.version` (and thus `db.json`'s `linux.version`) is derived from the release tag, not the constant `SOURCE_DATE_EPOCH`

**Status:** Accepted (2026-07-13) — decided by @mcfbytes; durable fix implemented.
**Impact:** `board/mister/de10nano/post-build.sh` (the `MISTER_VERSION` override),
`.github/workflows/release.yml` (derives + injects it, then verifies the built image),
`.github/workflows/publish-db.yml` + `scripts/gen-db-json.py` (db version from the
archive date). Resolves the "OPEN QUESTION" P4.4's `release.yml` left for P4.5/P2.6.
**Supersedes:** the P4.5 interim (db version from the GitHub Release `publishedAt` date),
which was a workaround for the problem this ADR now fixes at the source.
**Full rationale:** `docs/db-json-versioning.md`.

## The problem

The Downloader decides "is there a linux update?" by a strict string comparison of the
running system's `/MiSTer.version` against `db.json`'s `linux.version[-6:]`
(`docs/downloader-contract.md` §3). `/MiSTer.version` was baked from `SOURCE_DATE_EPOCH`,
which `configs/mister_de10nano_defconfig` pins to Buildroot's own commit date (P2.5/A9,
for reproducibility). So **every release built from the same `BUILDROOT_VERSION` baked an
identical `/MiSTer.version`** — two back-to-back releases would look identical to the
Downloader and the second would never be offered.

P4.5 first worked around this by deriving `db.json`'s version from the GitHub Release's
`publishedAt` date instead. That made new releases *detectable*, but introduced the
inverse bug: the on-device `/MiSTer.version` never advanced to match, so the box looked
"outdated" on *every* Downloader run and re-flashed — re-running `updateboot`, which wipes
U-Boot's saved environment — forever.

## Decision (the durable fix)

Make `/MiSTer.version` itself distinct per release, at the source:

- **`post-build.sh`** bakes `/MiSTer.version` from an optional **`MISTER_VERSION`** env var
  (6-digit `YYMMDD`) when set, falling back to the `SOURCE_DATE_EPOCH` date otherwise.
- **`release.yml`** derives `MISTER_VERSION` from the **tagged commit's UTC date** (fixed
  per commit ⇒ still reproducible), exports it into the build, then *verifies* the built
  image carries exactly that value.
- **`publish-db.yml` / `gen-db-json.py`** set `db.json`'s `linux.version` from the release
  **archive's `YYYYMMDD`** (whose last 6 chars are that same date), not `publishedAt`.

Result: `/MiSTer.version` == `release_YYYYMMDD.7z` date == `db.json` version — all distinct
per release and all reproducible for a given tag. The Downloader offers each real release
once and then correctly sees the box as up to date; no re-flash loop.

## Consequences

- **Reproducibility preserved.** A release pins `MISTER_VERSION` to a fixed tag date;
  non-release builds (CI push, local, the P4.3 reproducibility double-build) leave it
  unset and keep the constant `SOURCE_DATE_EPOCH` date, so their byte-identical-build
  guarantee is untouched. `SOURCE_DATE_EPOCH` still governs every other timestamp (file
  mtimes, ext4 superblock) — only the `/MiSTer.version` *string* is overridden.
- **Residual granularity limit (same as stock):** two releases tagged on the **same UTC
  day** map to one `YYMMDD` and collide. Acceptable; if same-day back-to-back releases are
  ever needed, set an explicit `MISTER_VERSION` in the release workflow env for the second.
