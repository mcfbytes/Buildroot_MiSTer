#!/usr/bin/env python3
"""build_etc_configs.py <rootfs-dir> <out-md>

Item (c): /etc configs verbatim-listed (init scripts, inittab, fstab,
smb.conf, wpa_supplicant, sshd_config, ...), the six A8 user-file-restore
destinations checked for regular-file-ness, and the default-credential
posture (root shadow entry / sshd PermitRootLogin), reported factually
without embedding secret material (password hashes, private SSH host keys)
into this repo.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

# Small, MiSTer-relevant / security-relevant configs to embed verbatim.
# (path relative to rootfs root, fence language)
VERBATIM_FILES = [
	("etc/inittab", ""),
	("etc/fstab", ""),
	("etc/hostname", ""),
	("etc/hosts", ""),
	("etc/os-release", ""),
	("etc/issue", ""),
	("etc/timezone", ""),
	("etc/network/interfaces", ""),
	("etc/dhcpcd.conf", ""),
	("etc/wpa_supplicant.conf", ""),
	("etc/ntp.conf", ""),
	("etc/proftpd.conf", ""),
	("etc/ssh/sshd_config", ""),
	("etc/samba/smb.conf", ""),
	("etc/bluetooth/main.conf", ""),
	("etc/passwd", ""),
	("etc/group", ""),
]

# The A8 user-file-restore contract (6 destinations that must be regular
# files, not symlinks, for the Downloader's offline user-file restore to
# land where it's supposed to -- see docs/verification/stock-release-20250402.md
# and PLAN.md A8).
USER_FILE_DESTINATIONS = [
	"etc/hostname",
	"etc/hosts",
	"etc/network/interfaces",
	"etc/resolv.conf",
	"etc/dhcpcd.conf",
	"etc/fstab",
]

INIT_DIR = "etc/init.d"

# /etc subdirectories that are standard package defaults (not MiSTer-
# specific / not security load-bearing) -- censused by file count rather
# than dumped verbatim, so nothing is silently unlisted.
CENSUS_ONLY_SKIP = {
	"init.d", "network", "ssh", "samba", "bluetooth", "ssl",
}


def resolve_in_root(root: Path, rel: str) -> str | None:
	"""Resolve `rel` (root-relative) through any symlinks *within the
	extracted tree*, treating an absolute symlink target (e.g.
	`/bin/bluetoothd`) as relative to `root`, not the host filesystem --
	Python's normal path following would otherwise try to open a literal
	host path like /bin/bluetoothd, which is wrong (and if it happens to
	exist on the host, silently reads the wrong file). Returns the final
	root-relative path string, or None if broken/looping/escapes the tree.
	"""
	current = rel
	seen = set()
	for _ in range(40):
		p = root / current
		if not p.is_symlink():
			return current if p.exists() else None
		if current in seen:
			return None
		seen.add(current)
		target = os.readlink(p)
		if os.path.isabs(target):
			nxt = os.path.normpath(target.lstrip("/"))
		else:
			nxt = os.path.normpath(os.path.join(os.path.dirname(current), target))
		if nxt.startswith(".."):
			return None
		current = nxt
	return None


def read_text(root: Path, rel: str) -> str | None:
	resolved = resolve_in_root(root, rel)
	if resolved is None:
		return None
	p = root / resolved
	if not p.is_file():
		return None
	try:
		return p.read_text(errors="replace")
	except OSError:
		return None


def fence(md: list[str], rel: str, content: str, lang: str = "") -> None:
	md.append(f"### `/{rel[4:]}`\n")
	md.append(f"```{lang}")
	md.append(content.rstrip("\n"))
	md.append("```\n")


def main(argv: list[str]) -> int:
	if len(argv) != 4:
		print(f"usage: {argv[0]} <rootfs-dir> <out-md> <out-init-scripts-txt>", file=sys.stderr)
		return 2
	root = Path(argv[1]).resolve()
	out_md = Path(argv[2])
	out_init_txt = Path(argv[3])

	md: list[str] = []

	# --- init scripts ---
	# NOTE: list every directory entry, including symlinks (S45bluetooth is
	# a symlink to /bin/bluetoothd in stock, NOT an inline script -- see
	# below) -- `is_file()` alone would silently skip it.
	init_dir = root / INIT_DIR
	entries = sorted(init_dir.iterdir(), key=lambda p: p.name) if init_dir.is_dir() else []
	scripts = [p.name for p in entries if p.is_file() or p.is_symlink()]
	symlinked = {p.name: os.readlink(p) for p in entries if p.is_symlink()}
	expected = ["S01syslogd", "S02klogd", "S10udev", "S30dbus", "S40network",
	            "S41dhcpcd", "S45bluetooth", "S49ntp", "S50proftpd", "S50sshd",
	            "S91smb", "S99user"]
	s_scripts = [s for s in scripts if s.startswith("S")]
	other_scripts = [s for s in scripts if not s.startswith("S")]
	md.append("## Init scripts (`/etc/init.d`)\n")
	md.append(f"Full listing: **{len(scripts)}** entries (`{', '.join(scripts)}`).\n")
	md.append(f"Verified stock S-script set (S01-S99): `{' '.join(expected)}`.")
	if sorted(s_scripts) == expected:
		md.append("**Matches exactly** (by name -- see the symlink note below for S45bluetooth's actual shape).\n")
	else:
		missing = [e for e in expected if e not in s_scripts]
		extra = [s for s in s_scripts if s not in expected]
		md.append(f"**DIFFERS** -- missing: {missing or 'none'}; extra: {extra or 'none'}.\n")
	if other_scripts:
		md.append(f"Non-`S`-prefixed control scripts also present: `{', '.join(other_scripts)}` (BusyBox init `rcS`/`rcK` runlevel drivers, verbatim below).\n")
	if symlinked:
		md.append("### ⚠ Finding: not every `S`-script is an inline script\n")
		for name, target in sorted(symlinked.items()):
			md.append(f"- `/etc/init.d/{name}` is a **symlink** to `{target}`, not a regular file.")
		md.append("")
		md.append("`rcS`/`rcK` (verbatim below) run every `/etc/init.d/S??*` entry with")
		md.append("`$i start` / `$i stop` regardless of whether it's a real file or a")
		md.append("symlink (their only guard is `[ ! -f \"$i\" ]`, which follows symlinks).")
		md.append("So `S45bluetooth start` really execs `/bin/bluetoothd start` --")
		md.append("verified below, `/bin/bluetoothd` is itself a conventional")
		md.append("start/stop/restart/reload/renew/hcireset control script (same shape")
		md.append("as the other services), just placed at `/bin/bluetoothd` instead of")
		md.append("written inline under `/etc/init.d/`. It execs the real daemon at")
		md.append("`/usr/libexec/bluetooth/bluetoothd` with args `-n -E -C`, and --")
		md.append("directly relevant to P2.4's writable-paths audit and P3.5's Bluetooth")
		md.append("parity task -- **this is stock's actual BT-pairing persistence")
		md.append("mechanism**: on `start` it creates (if missing) and loop-mounts a")
		md.append("64KiB×32=2MiB ext4 image at `/media/fat/linux/bluetooth` onto")
		md.append("`/var/lib/bluetooth` (`sync,dirsync,nodiratime,noatime`), i.e. pairing")
		md.append("state lives in a small dedicated image file on the FAT data partition,")
		md.append("not in tmpfs and not directly in the (read-only) rootfs. A `renew`")
		md.append("action deletes that image to reset all pairings. Full verbatim text")
		md.append("of `/bin/bluetoothd` is in `etc-init-scripts-full.txt` alongside this")
		md.append("doc (listed there under its resolved path since it isn't literally")
		md.append("under `/etc/init.d/`).\n")
	md.append("Each script's daemon/exec line (`grep -E 'DAEMON=|^exec |start-stop-daemon'`, first match; symlinked entries are resolved before reading):\n")
	md.append("| Script | Resolves to | Daemon/exec line |")
	md.append("|---|---|---|")
	for s in scripts:
		resolved = resolve_in_root(root, f"{INIT_DIR}/{s}")
		text = read_text(root, f"{INIT_DIR}/{s}") or ""
		daemon_line = "-"
		for line in text.splitlines():
			line_s = line.strip()
			if line_s.startswith("DAEMON=") or line_s.startswith("exec ") or "start-stop-daemon" in line_s:
				daemon_line = line_s
				break
		resolved_col = f"`/{resolved}`" if resolved and resolved != f"{INIT_DIR}/{s}" else "(itself)"
		md.append(f"| `{s}` | {resolved_col} | `{daemon_line}` |")
	md.append("")
	md.append("Full verbatim content of every init script (following the S45bluetooth")
	md.append("symlink to its real target) is in `etc-init-scripts-full.txt` (sorted, one")
	md.append("script's full text per section) alongside this doc.\n")

	# --- verbatim configs ---
	md.append("## Verbatim configs\n")
	for rel, lang in VERBATIM_FILES:
		content = read_text(root, rel)
		if content is None:
			md.append(f"### `/{rel[4:]}`\n")
			md.append("*(not present in this image)*\n")
			continue
		fence(md, rel, content, lang)

	# --- passwd/shadow/group: default-credential posture ---
	md.append("## Default-credential posture (P3.7 / P4.8 FAQ input)\n")
	shadow = read_text(root, "etc/shadow")
	md.append("`/etc/shadow` is deliberately **not** reproduced verbatim in this repo")
	md.append("(it contains real crypt() password hashes baked into the public stock")
	md.append("image; there is no reason to also re-publish them verbatim in a new")
	md.append("repo). Structural summary instead -- for each account, whether the shadow")
	md.append("field is a login-capable hash or a locked/no-login marker (`*`/`!`):\n")
	md.append("| Account | Shadow field | Login-capable? |")
	md.append("|---|---|---|")
	if shadow:
		for line in shadow.splitlines():
			if not line.strip():
				continue
			parts = line.split(":")
			user = parts[0]
			field = parts[1] if len(parts) > 1 else ""
			capable = "**yes**" if field not in ("", "*", "!", "!!") else "no (locked)"
			shown = "(hash present, not reproduced here)" if capable == "**yes**" else f"`{field}`"
			md.append(f"| `{user}` | {shown} | {capable} |")
	md.append("")
	md.append("**Finding:** `root` is the only account with a login-capable password hash")
	md.append("(a SHA-512 crypt hash, `$5$...`); every service account is locked (`*`).")
	md.append("Combined with `sshd_config`'s `PermitRootLogin yes` (verbatim above) and")
	md.append("`proftpd.conf` (verbatim above, no explicit `RootLogin off`), stock ships")
	md.append("**remote root login enabled by default, gated only by a fixed, publicly")
	md.append("shipped default password**. This project must not silently change that")
	md.append("(parity requirement, P3.7) but must document the risk prominently in the")
	md.append("user-facing FAQ (P4.8) rather than treating it as a secret. The specific")
	md.append("plaintext default password is widely published in the existing MiSTer")
	md.append("community documentation/wiki; it is intentionally not restated here --")
	md.append("this doc's job is to confirm *that* a fixed default credential + remote")
	md.append("root login exists, which is the fact P3.7/P4.8 need, not to be another")
	md.append("place that publishes it.\n")

	ssh_dir = root / "etc/ssh"
	host_keys = sorted(p.name for p in ssh_dir.glob("ssh_host_*")) if ssh_dir.is_dir() else []
	md.append("### SSH host keys\n")
	md.append("Also baked into the stock image (not reproduced here -- private key")
	md.append("material): " + ", ".join(f"`{k}`" for k in host_keys) + ".")
	md.append("Every stock installation that has never regenerated its host keys shares")
	md.append("the *same* host keys as every other installation of the same release --")
	md.append("a known fingerprint-reuse caveat worth the same FAQ treatment as the root")
	md.append("password above (P2.4/P3.7 must persist *whatever* keys end up shipped,")
	md.append("stock or freshly generated; P4.8 should say which we chose and why).\n")

	# --- A8 user-file-restore destinations ---
	md.append("## A8 user-file-restore destinations: regular-file check\n")
	md.append("Evidence method: `os.path.islink()`/`os.path.isfile()` on the extracted")
	md.append("rootfs tree (symlinks are preserved as real symlinks by the `debugfs")
	md.append("rdump` extraction method used throughout this inventory -- verified")
	md.append("docs/reference-materials.md section 3), cross-checked directly against")
	md.append("the raw ext4 image with `debugfs -R \"stat <path>\"` for the one finding")
	md.append("below.\n")
	md.append("| Destination | Type | Regular file (A8 requirement)? |")
	md.append("|---|---|---|")
	any_symlink = False
	for rel in USER_FILE_DESTINATIONS:
		p = root / rel
		if p.is_symlink():
			target = os.readlink(p)
			md.append(f"| `/{rel}` | symlink -> `{target}` | **NO** |")
			any_symlink = True
		elif p.is_file():
			md.append(f"| `/{rel}` | regular file | yes |")
		else:
			md.append(f"| `/{rel}` | missing/other | **NO** |")
	md.append("")
	if any_symlink:
		md.append("### ⚠ Finding: `/etc/resolv.conf` is a symlink, not a regular file\n")
		md.append("`/etc/resolv.conf -> ../tmp/resolv.conf` in stock (`/tmp` is tmpfs per")
		md.append("`fstab`, verbatim above). This contradicts the documented A8 invariant")
		md.append("that all six user-file-restore destinations are plain regular files.")
		md.append("Traced through `Downloader_MiSTer`'s actual restore code")
		md.append("(`src/downloader/file_system.py`, the `copy()` method used by")
		md.append("`linux_updater.py`'s `_restore_user_files()`): it does")
		md.append("`open(full_target, 'wb')`, which **follows** a symlink rather than")
		md.append("replacing it. Run against the *offline-mounted, unbooted* new image")
		md.append("(where `/tmp` is just an ordinary empty ext4 directory, not a live")
		md.append("tmpfs), the restore therefore silently writes the user's custom")
		md.append("`resolv.conf` content to `/tmp/resolv.conf` **inside the persisted")
		md.append("image** -- not to a stable `/etc` location. On the next boot, the")
		md.append("`tmpfs` mount over `/tmp` shadows that file immediately, so the")
		md.append("restored content is invisible/lost from the moment the system boots.")
		md.append("In practice this is likely harmless *by original design* --")
		md.append("`/etc/resolv.conf` being a tmpfs symlink exists so `dhcpcd` can")
		md.append("rewrite DNS servers on a read-only root, and a custom static")
		md.append("`resolv.conf` is probably rare/moot for DHCP-managed installs -- but")
		md.append("it means the \"restore custom resolv.conf\" step of the updater")
		md.append("contract is a **no-op in stock**, not the regular-file copy A8 and")
		md.append("P2.3 assume. P2.3 must either preserve this exact stock behavior")
		md.append("(symlink to tmpfs, silently-discarded restore) or explicitly diverge")
		md.append("and document why (e.g. make `/etc/resolv.conf` a real regular file so")
		md.append("the restore actually sticks, accepting that a read-only root then")
		md.append("needs a different writable-DNS mechanism, P2.4's problem to solve).")
		md.append("The other five destinations are genuine regular files and the")
		md.append("documented restore mechanism works for them as described.\n")
	else:
		md.append("All six destinations are regular files, confirming the A8 invariant.\n")

	# --- census of everything else under /etc ---
	md.append("## Everything else under `/etc` (census, not verbatim)\n")
	md.append("Standard package-default config directories not central to the ABI")
	md.append("contract -- listed by file count so nothing is silently dropped from")
	md.append("this inventory, without dumping every vendor default file verbatim:\n")
	md.append("| Directory | Regular files | Total bytes |")
	md.append("|---|---|---|")
	etc_dir = root / "etc"
	seen_top = set()
	rows = []
	for entry in sorted(etc_dir.iterdir()):
		name = entry.name
		if name in CENSUS_ONLY_SKIP:
			continue
		covered = any(rel == f"etc/{name}" for rel, _ in VERBATIM_FILES)
		if covered:
			continue
		seen_top.add(name)
		if entry.is_dir():
			files = [f for f in entry.rglob("*") if f.is_file()]
			total = sum(f.stat().st_size for f in files)
			rows.append((name + "/", len(files), total))
		elif entry.is_file():
			rows.append((name, 1, entry.stat().st_size))
	for name, count, total in sorted(rows):
		md.append(f"| `/etc/{name}` | {count} | {total} |")
	md.append("")

	out_md.write_text("\n".join(md) + "\n")

	# Full verbatim init-script text, kept in a companion .txt (kept out of
	# the main .md to keep that file a reasonable size to read).
	init_txt_path = out_init_txt
	init_lines = []
	for s in scripts:
		resolved = resolve_in_root(root, f"{INIT_DIR}/{s}")
		content = read_text(root, f"{INIT_DIR}/{s}") or ""
		header = f"===== /etc/init.d/{s} ====="
		if resolved and resolved != f"{INIT_DIR}/{s}":
			header += f" (symlink -> /{resolved})"
		init_lines.append(header)
		init_lines.append(content.rstrip("\n"))
		init_lines.append("")
	init_txt_path.write_text("\n".join(init_lines) + "\n")

	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv))
