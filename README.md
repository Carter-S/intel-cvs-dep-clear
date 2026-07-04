# intel-cvs-dep-clear

**Make the built-in MIPI camera work on Intel Arrow Lake laptops on Linux**
(e.g. Lenovo ThinkPad X1 Carbon Gen 13) — end to end: kernel module to
unblock the sensor, a bridge so Chrome/Zoom/Meet can use it, and a live
tuning UI for image quality.

> **Status: EXPERIMENTAL but daily-driven.** This is a stopgap until a real
> Intel CVS (ARL) driver and an ov08x40 calibration land upstream.

There are **three separate problems** between you and a working camera on
this hardware. This repo solves all three:

| # | Problem | Fix in this repo |
|---|---------|------------------|
| 1 | Sensor never enumerates (no i2c client, `cam -l` empty) | `cvs_dep_clear` kernel module (`install.sh`) |
| 2 | libcamera works but Chrome/Zoom/Meet can't see the camera | v4l2loopback bridge (`setup-relay.sh`) |
| 3 | Image is washed out / wrong colours | softISP tuning file + live tuner (`tuner.py`) |

## Quick start

```bash
git clone https://github.com/Carter-S/intel-cvs-dep-clear.git
cd intel-cvs-dep-clear
sudo ./setup.sh          # installs everything: packages, module, bridge, tuning
```

That's it — apps should list a webcam called **"Virtual Camera"**. Then,
optionally, tune the image live (exposure, colour, vibrance, mirror):

```bash
sudo python3 tuner.py    # -> http://127.0.0.1:8787
```

Each step can also be run individually (`install.sh` = kernel module,
`setup-relay.sh` = app bridge + tuning + vibrance element) — see below.

---

## Problem 1: the sensor never enumerates

### Symptoms

- `cam -l` shows no cameras; `libcamera` reports `No sensor found for /dev/media0`
- `dmesg`: `int3472-discrete INT3472:0b: INT3472 seems to have no dependents.`
  and, early in boot, `cannot find GPIO chip INTC10B2:00, deferring`
- `/sys/bus/acpi/devices/OVTI08F4:00` exists (status 15) but has **no
  `physical_node`** — the sensor is never instantiated as an I²C client
- `/sys/bus/acpi/devices/INTC10E0:00` exists and nothing binds to it
- All the right modules are loaded (`intel_ipu6_isys`, `usbio`, `gpio_usbio`,
  `i2c_usbio`, `intel_skl_int3472_discrete`, `ov08x40`) — still nothing

### Root cause

The camera sensor (OmniVision OV08X40, ACPI HID `OVTI08F4`) lists the
**Intel CVS aggregator `INTC10E0`** ("Computer Vision Sensing", an always-on
vision co-processor that shares the sensor with the host) in its ACPI `_DEP`.
The kernel honors that dependency — `drivers/acpi/scan.c`:

```
"INTC10E0", /* CVS (ARL) driver must be loaded to allow camera streaming */
```

Enumeration of the sensor is deferred until an INTC10E0 driver calls
`acpi_dev_clear_dependencies()`. **No such driver exists in mainline** (Intel's
out-of-tree [vision-drivers](https://github.com/intel/vision-drivers)
`intel_cvs` only supports Lunar Lake via LJCA). The sensor waits forever.

### Fix

`cvs_dep_clear.c` performs exactly the call the missing driver would make:

```c
adev = acpi_dev_get_first_match_dev("INTC10E0", NULL, -1);
acpi_dev_clear_dependencies(adev);
```

The ACPI core then enumerates the deferred sensor, i2c-core creates the
client on the USBIO bus, `ov08x40` probes, and `ipu-bridge` wires the media
graph. `sudo ./install.sh` registers it with DKMS and loads it at boot
(order doesn't matter — the dependency count only reaches zero when the
int3472/USBIO side is also ready).

What success looks like, ~3s after loading:

```
cvs_dep_clear: clearing ACPI _DEP on INTC10E0:00
ov08x40 i2c-OVTI08F4:00: supply dovdd not found, using dummy regulator
$ cam -l
Available cameras:
1: Internal front camera (\_SB_.PC00.LNK1)
```

("dummy regulator" lines are normal on int3472 platforms.)

---

## Problem 2: apps can't see the camera

libcamera working ≠ working webcam. IPU6 MIPI cameras don't produce a
classic `/dev/video*` device; apps need either native libcamera/PipeWire
support or a bridge.

**Chrome's native path is broken.** With `chrome://flags` →
"PipeWire Camera support" enabled (Chrome 148 + PipeWire 1.6), pages that
request the camera **render fully black** — the stream setup wedges the tab
compositing before a single frame flows. Leave that flag **Disabled**.

**The bridge that works:** `v4l2-relayd` + `v4l2loopback` relays
`libcamerasrc` into a virtual V4L2 device ("Virtual Camera") that every app
(Chrome, Zoom, Slack, OBS) treats as a normal USB-style webcam.
`sudo ./setup-relay.sh` configures all of it, including two non-obvious
fixes we lost hours to:

1. **systemd sandbox blocks the software ISP.** `v4l2-relayd`'s unit ships
   `DevicePolicy=closed` without `/dev/dma_heap` / `/dev/udmabuf`, so
   libcamera's softISP fails (`Could not open any dma-buf provider`) and the
   camera produces nothing. A drop-in adds `DeviceAllow=char-dma_heap` and
   `DeviceAllow=/dev/udmabuf`.
2. **The relay input caps must pin format AND framerate.**
   `VIDEOSRC="libcamerasrc ! video/x-raw,format=RGBA,width=1280,height=720,framerate=30/1 ! videoconvert"`.
   Without explicit `framerate`, buffer timestamps confuse the relay and it
   floods the loopback with black filler frames — apps see ~1fps, flickering
   to black. Asking libcamerasrc for 720p directly also keeps CPU low (the
   softISP scales on the GPU).

**Caveat:** the loopback accepts **one reader at a time** (second reader
gets `S_FMT: Device or resource busy`). Close other camera apps if the
picture is black, and quit `tuner.py` before joining a call.

---

## Problem 3: image quality (washed out, wrong colours)

The softISP has no calibration for ov08x40 — it logs
`Configuration file 'ov08x40.yaml' not found ... falling back to
uncalibrated.yaml` and renders flat, hazy colour. Real fixes:

- **Tuning file:** `data/ov08x40.yaml` (installed by `setup-relay.sh`)
  provides colour-correction matrices we calibrated grey-world style on a
  real unit. libcamera picks it up by sensor name at
  `/usr/share/libcamera/ipa/simple/ov08x40.yaml`.
- **Live tuner:** `sudo python3 tuner.py` → http://127.0.0.1:8787 — sliders
  for saturation / per-channel gains / brightness / contrast / gamma /
  mirror / exposure target / **vibrance**, with a live 30fps preview. Every
  change rewrites the tuning file + relay config and restarts the relay.
  Settings persist.
- **Digital vibrance:** `gst-vibrance/` is a small out-of-tree GStreamer
  element (`vibrance amount=0..2`) implementing NVIDIA-style vibrance:
  saturation boost weighted towards *muted* colours, so the image pops
  without wrecking skin tones. CPU (in-place, ~740fps at 720p on ARL-U).
  We first implemented it as a `glshader` GPU filter — don't: gst-gl's
  headless paths tear/flicker on this stack (dma-buf sync). The CPU element
  is deterministic and costs ~4% of one core at 30fps.

### Known limitation: exposure

libcamera ≤ 0.7 (and master at time of writing) has **no exposure control
in the softISP** — the AGC brightness target is a hardcoded constant, so
backlit scenes blow out and no config can prevent it.
`patches/softisp-agc-target.patch` (**verified working**) makes the target
read the `SOFTISP_AGC_TARGET` environment variable (which `tuner.py`'s "Exposure
target" slider already writes). Apply it to Ubuntu's libcamera source,
rebuild `ipa_soft_simple.so`, and replace the one file (the module runs
isolated when unsigned — still works). Note a `libcamera-ipa` package
update will silently restore the stock module — re-install after upgrades. Physical advice that beats software:
don't sit with a bright light behind you, and wipe the lens.

---

## Troubleshooting quick reference

| Symptom | Cause | Fix |
|---|---|---|
| `INT3472 seems to have no dependents` | INTC10E0 dep never cleared | load `cvs_dep_clear` |
| `cannot find GPIO chip INTC10B2:00, deferring` at boot | USBIO probes after int3472 | harmless; resolves once `gpio_usbio` registers |
| `cam -l` empty, `OVTI08F4:00` has no `physical_node` | sensor enumeration deferred | load `cvs_dep_clear` |
| Chrome page black with PipeWire camera flag | broken Chrome/PipeWire path | disable the flag, use the relay |
| Virtual Camera exists, only black frames | softISP dma-buf blocked by sandbox | dmabuf drop-in (`setup-relay.sh`) |
| ~1fps + flicker to black | missing `framerate` in relay caps | pin caps (`setup-relay.sh`) |
| `Device or resource busy` on the loopback | second reader | one camera app at a time |
| Washed-out / green / pale image | no tuning file for ov08x40 | `data/ov08x40.yaml` + `tuner.py` |
| Blown-out highlights | AGC target hardcoded | `patches/softisp-agc-target.patch`, fix lighting |

## Verified working on

| Machine | SoC | Kernel | Sensor | Status |
|---|---|---|---|---|
| Lenovo ThinkPad X1 Carbon Gen 13 (21NX) | Core Ultra 7 255U (ARL-U) | 7.0.0-22 (Ubuntu) | OV08X40 | ✅ 30 fps in Google Meet, calibrated colour |

PRs welcome — especially additional machines for this table and a proper
AIQB-derived ov08x40 calibration.

## Watch upstream

- [intel/ipu6-drivers#281](https://github.com/intel/ipu6-drivers/issues/281) — INT3472 GPIO / Lattice aggregator support
- [intel/ipu6-drivers#373](https://github.com/intel/ipu6-drivers/issues/373)
- [intel/vision-drivers](https://github.com/intel/vision-drivers) — a real `intel_cvs` for ARL would obsolete problem 1
- [libcamera softISP tuning patches](https://patchwork.libcamera.org/patch/26699/) — factory-style calibration for sibling sensors

## Requirements

Kernel with the in-tree stack: IPU6, USBIO (mainline ≥ 6.18), `int3472`,
`ov08x40`. On older Ubuntu kernels: `linux-modules-usbio-generic`
`linux-modules-ipu6-generic`. For apps: `pipewire-libcamera` optional; the
relay path needs only what `setup-relay.sh` installs. **Secure Boot:** the
module is unsigned — use the DKMS install (MOK signing) or disable SB.

## License

GPL-2.0.
