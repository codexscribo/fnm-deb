#!/usr/bin/env bash
# Install, smoke-test, and uninstall a built fnm .deb inside a distro
# container.
#
# Usage: test-deb.sh <fnm-deb> <expected-version>
# Intended to run as root inside an Ubuntu/Debian Docker container.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <fnm-deb> <expected-version>" >&2
  exit 1
fi

deb_path="$1"
expected_version="$2"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$deb_path" ]] || fail "deb file not found: $deb_path"

export DEBIAN_FRONTEND=noninteractive

# Official Ubuntu/Debian Docker images configure dpkg to skip installing
# man pages (and other docs) to keep images small. fnm ships no man page,
# but this is kept for parity in case future doc files are added.
rm -f /etc/dpkg/dpkg.cfg.d/excludes

apt-get update -qq || fail "apt-get update"

# Generic stock-package check: there is no "fnm" package in Debian/Ubuntu's
# official archives today, but check dynamically rather than hardcoding
# that assumption, so this script stays correct if that ever changes.
if apt-cache show fnm >/dev/null 2>&1; then
  echo "==> Stock 'fnm' package found in this distro's archive; installing it first"
  apt-get install -y fnm || fail "apt-get install (stock fnm)"
  command -v fnm >/dev/null 2>&1 || fail "fnm not found on PATH after installing stock package"
  echo "Stock version: $(fnm --version)"
else
  echo "==> No stock 'fnm' package in this distro's archive; skipping upgrade-path setup"
fi

echo "==> Installing $deb_path"
apt-get install -y "./${deb_path}" || fail "apt-get install"

echo "==> Verifying installed version"
hash -r
command -v fnm >/dev/null 2>&1 || fail "fnm not found on PATH after install"
version_output="$(fnm --version)"
echo "$version_output" | grep -qF "$expected_version" || fail "fnm --version does not reflect '$expected_version' (got: $version_output)"

echo "==> Verifying installation"
fnm --help >/dev/null || fail "fnm --help failed"
fnm list >/dev/null || fail "fnm list failed"
# --shell bash avoids fnm's parent-process shell inference, which is
# unreliable in a headless container with no real interactive shell.
fnm env --shell bash >/dev/null || fail "fnm env failed"

dpkg -s fnm | grep -q "^Status: install ok installed" || fail "dpkg status for fnm is not 'install ok installed'"

echo "==> Uninstalling fnm"
apt-get remove -y fnm || fail "apt-get remove fnm"
hash -r

if command -v fnm >/dev/null 2>&1; then
  fail "fnm still present after removal"
fi

# A package with no conffiles (ours has none) is fully purged from dpkg's
# database by a plain "remove", so dpkg -s either reports it unknown or
# reports it in a non-installed (deinstall/config-files) state. Both are
# valid confirmations of removal; only "install ok installed" is a failure.
if dpkg -s fnm 2>/dev/null | grep -q "^Status: install ok installed"; then
  fail "fnm still reports as installed after removal"
fi

echo "PASS: all checks succeeded"
