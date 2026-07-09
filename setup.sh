#!/bin/bash
# One-command setup: everything needed for a working, tunable camera.
#   sudo ./setup.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo ./setup.sh"; exit 1; }
cd "$(dirname "$0")"

echo "==== [1/4] installing packages ===="
apt-get update -qq || true
apt-get install -y \
    build-essential "linux-headers-$(uname -r)" dkms \
    v4l2-relayd v4l2loopback-dkms gstreamer1.0-libcamera \
    libgstreamer-plugins-base1.0-dev libcamera-tools

echo
echo "==== [2/4] kernel module (sensor enumeration) ===="
./install.sh

echo -n "waiting for the sensor to enumerate"
for i in $(seq 1 20); do
    ls /sys/bus/i2c/devices/ 2>/dev/null | grep -qi OVTI && break
    echo -n "."; sleep 1
done
echo
if ls /sys/bus/i2c/devices/ 2>/dev/null | grep -qi OVTI; then
    echo "sensor enumerated OK"
else
    echo "WARNING: sensor did not appear within 20s - check 'dmesg | grep -i cvs_dep'"
fi

echo
echo "==== [3/4] app bridge + tuning + vibrance ===="
./setup-relay.sh

echo
echo "==== [3.5/4] suspend/resume self-healing ===="
make -C resume-recovery install && echo "resume recovery hook installed"

echo
echo "==== [4/4] done ===="
cam -l 2>/dev/null | grep -A3 "Available" || true
echo
echo "A webcam called 'Virtual Camera' should now be available in your apps."
echo "Tune the image live:   sudo python3 $(pwd)/tuner.py   -> http://127.0.0.1:8787"
echo "(quit the tuner before joining a call - one reader at a time)"
