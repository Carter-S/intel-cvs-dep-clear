#!/bin/bash
# Set up the v4l2-relayd bridge that exposes the libcamera softISP camera
# as a plain V4L2 webcam ("Virtual Camera") that Chrome/Zoom/etc can use.
# Run AFTER install.sh has the sensor enumerating (cam -l lists a camera).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

echo "== installing bridge packages =="
apt-get install -y v4l2-relayd v4l2loopback-dkms gstreamer1.0-libcamera

echo "== relay input: libcamera with explicit caps =="
# framerate in caps is REQUIRED: without it the relay floods the loopback
# with black filler frames (mistimed buffers) and apps see ~1fps + flicker.
cat > /etc/v4l2-relayd.d/camera.conf <<'EOF'
VIDEOSRC="libcamerasrc ! video/x-raw,format=RGBA,width=1280,height=720,framerate=30/1 ! videoconvert"
EOF

echo "== allow the softISP to allocate dma-buf frame buffers =="
# v4l2-relayd's unit sandbox (DevicePolicy=closed) blocks /dev/dma_heap and
# /dev/udmabuf; without them libcamera's software ISP dies at startup
# ("Could not open any dma-buf provider") and the camera outputs nothing.
mkdir -p /etc/systemd/system/v4l2-relayd@.service.d
cat > /etc/systemd/system/v4l2-relayd@.service.d/dmabuf.conf <<'EOF'
[Service]
DeviceAllow=char-dma_heap
DeviceAllow=/dev/udmabuf
EOF

echo "== calibrated softISP tuning file (colour) =="
if [ ! -e /usr/share/libcamera/ipa/simple/ov08x40.yaml ]; then
    cp "$(dirname "$0")/data/ov08x40.yaml" /usr/share/libcamera/ipa/simple/
    echo "installed data/ov08x40.yaml (tune further with tuner.py)"
else
    echo "keeping existing /usr/share/libcamera/ipa/simple/ov08x40.yaml"
fi

echo "== pipeline-from-file override (multi-element pipelines from tuner.py) =="
cat > /etc/systemd/system/v4l2-relayd@.service.d/pipeline-file.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/bin/sh -c 'DEVICE=$(grep -l -m1 -E "^${CARD_LABEL}$" /sys/devices/virtual/video4linux/*/name | cut -d/ -f6); if [ -r /etc/v4l2-relayd.d/videosrc.pipeline ]; then VIDEOSRC="$(cat /etc/v4l2-relayd.d/videosrc.pipeline)"; fi; exec /usr/bin/v4l2-relayd -i "$${VIDEOSRC}" $${SPLASHSRC:+-s "${SPLASHSRC}"} -o "appsrc name=appsrc caps=video/x-raw,format=${FORMAT},width=${WIDTH},height=${HEIGHT},framerate=${FRAMERATE} ! videoconvert ! v4l2sink name=v4l2sink device=/dev/$${DEVICE}" $EXTRA_OPTS'
EOF

echo "== vibrance plugin (optional, needs gst dev headers) =="
if pkg-config --exists gstreamer-video-1.0 2>/dev/null; then
    make -C "$(dirname "$0")/gst-vibrance" install && echo "vibrance element installed"
else
    echo "SKIPPED: install libgstreamer-plugins-base1.0-dev then run:"
    echo "  sudo make -C gst-vibrance install"
fi

echo "== loading loopback + starting relay =="
modprobe v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
systemctl daemon-reload
systemctl restart v4l2-relayd.service v4l2-relayd@camera.service

echo
echo "Done. Apps should now list a webcam called 'Virtual Camera'."
echo "NOTE: in Chrome keep chrome://flags 'PipeWire Camera support' DISABLED -"
echo "the native PipeWire path renders a black page on current Chrome/PipeWire."
echo "Only one app can read the virtual camera at a time."
