#!/bin/bash
# Remove cvs-dep-clear: DKMS module, boot config, and source copy.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

VERSION=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' "$(dirname "$0")/dkms.conf")

rm -f /etc/modules-load.d/cvs-dep-clear.conf
dkms remove "cvs-dep-clear/${VERSION}" --all 2>/dev/null || true
rm -rf "/usr/src/cvs-dep-clear-${VERSION}"

echo "Removed. The module stays loaded until reboot (or: sudo rmmod cvs_dep_clear)."
