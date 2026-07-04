#!/bin/bash
# Install cvs-dep-clear via DKMS and enable loading at boot.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$(dirname "$0")/dkms.conf")
SRC="/usr/src/cvs-dep-clear-${VERSION}"

command -v dkms >/dev/null || { echo "Installing dkms..."; apt-get install -y dkms; }

echo "== copying source to ${SRC} =="
mkdir -p "${SRC}"
cp "$(dirname "$0")"/{cvs_dep_clear.c,Makefile,dkms.conf} "${SRC}/"

echo "== dkms add/build/install =="
dkms add "cvs-dep-clear/${VERSION}" 2>/dev/null || true
dkms build "cvs-dep-clear/${VERSION}"
dkms install "cvs-dep-clear/${VERSION}"

echo "== enable load at boot =="
echo cvs_dep_clear > /etc/modules-load.d/cvs-dep-clear.conf

echo "== loading now =="
modprobe cvs_dep_clear

echo
echo "Done. Give it a few seconds, then check:"
echo "  ls /sys/bus/i2c/devices/ | grep -i ovti"
echo "  cam -l"
