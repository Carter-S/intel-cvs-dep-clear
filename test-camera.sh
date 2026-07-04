#!/bin/bash
# One-shot test: load cvs_dep_clear and watch the camera stack come up.
# Run as: sudo ./test-camera.sh   (from ~/cvs-dep-clear, after a FRESH boot)
set -u
cd "$(dirname "$0")"

echo "== pre-flight: int3472 must be bound (fresh boot state) =="
if ! ls /sys/bus/platform/drivers/int3472-discrete/ | grep -q INT3472; then
    echo "FAIL: INT3472 not bound to its driver. Reboot first, then re-run."
    exit 1
fi
echo "int3472: bound OK"

echo
echo "== loading cvs_dep_clear =="
insmod ./cvs_dep_clear.ko || { echo "insmod failed"; exit 1; }

echo "waiting for async ACPI enumeration + driver probes..."
for i in $(seq 1 15); do
    sleep 1
    ls /sys/bus/i2c/devices/ 2>/dev/null | grep -qi OVTI && break
done

echo
echo "== sensor i2c client =="
ls /sys/bus/i2c/devices/ | grep -i OVTI || echo "no OVTI client appeared (see dmesg below)"

echo
echo "== relevant dmesg since module load =="
dmesg | grep -iE "cvs_dep_clear|ovti|ov08x40|int3472|ipu6|ipu.bridge" | tail -25

echo
echo "== media graph =="
for m in /dev/media*; do
    echo "--- $m ---"
    media-ctl -d "$m" -p 2>/dev/null | grep -iE "entity|ov08x40" | head -10
done

echo
echo "== libcamera =="
runuser -u "${SUDO_USER:-$USER}" -- cam -l 2>/dev/null || cam -l

echo
echo "Done. If a camera is listed above: WE HAVE A CAMERA."
echo "If ov08x40 probe failed on chip-id/i2c read: CVS chip still owns the sensor;"
echo "next step is the GPIO handshake (pins 5/7 on INTC10B2) - go back to Claude."
