#!/usr/bin/env bash
# hostshim.sh -- make sure Buildroot sees a GNU `install`.
#
# usage: scripts/hostshim.sh <shim-dir>
#
# Buildroot refuses to build when /usr/bin/install is uutils coreutils
# (support/dependencies/dependencies.sh; https://github.com/uutils/coreutils/issues/12166),
# which Debian/Ubuntu's coreutils-from-uutils installs as the default while
# shipping GNU's as `gnuinstall`. Upstream's advice is update-alternatives,
# which needs root and mutates the developer's machine. Instead: a directory
# holding one `install` symlink to a GNU install, which the Makefile prepends
# to PATH for Buildroot only. A no-op on a host whose install is already GNU
# (prints nothing, creates nothing); fails loudly when no GNU install exists.
# CI runs it as a fail-fast check before spending hours on a build.
set -euo pipefail
shim_dir=${1:?usage: hostshim.sh <shim-dir>}
if install --version 2>/dev/null | grep -q 'GNU coreutils'; then
	exit 0
fi
gnu=$(command -v gnuinstall 2>/dev/null || true)
if [ -z "$gnu" ]; then
	cat >&2 <<MSG
FATAL: your 'install' is not GNU coreutils:
    $(install --version 2>&1 | head -1)
Buildroot refuses to build with it and no GNU 'install' was found to substitute.
Install GNU coreutils, e.g.:  sudo apt-get install gnu-coreutils   # provides /usr/bin/gnuinstall
MSG
	exit 1
fi
mkdir -p "$shim_dir"
ln -sf "$gnu" "$shim_dir/install"
echo "==> host 'install' is not GNU; shimming $gnu into PATH for Buildroot"
