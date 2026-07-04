# intel-cvs-dep-clear

**Fix the built-in MIPI camera on Intel Arrow Lake laptops on Linux** (e.g. Lenovo
ThinkPad X1 Carbon Gen 13) — a tiny kernel module that unblocks camera sensor
enumeration on platforms with the Intel CVS (Computer Vision Sensing) aggregator
`INTC10E0`, for which no mainline Linux driver exists yet.

> **Status: EXPERIMENTAL.** This is a stopgap until a real Intel CVS (ARL) driver
> lands upstream. It works by satisfying an ACPI dependency, not by implementing
> the CVS handshake. See [Limitations](#limitations).

## Symptoms this addresses

You have an Arrow Lake (Core Ultra 200U/200V series) laptop and:

- The built-in camera does not appear: `cam -l` shows no cameras, no `/dev/video*`
  capture device, `libcamera` reports `No sensor found for /dev/media0`.
- `dmesg` shows:
  ```
  int3472-discrete INT3472:0b: INT3472 seems to have no dependents.
  int3472-discrete INT3472:0c: INT3472 seems to have no dependents.
  ```
  and earlier in boot:
  ```
  int3472-discrete INT3472:0b: cannot find GPIO chip INTC10B2:00, deferring
  ```
- The sensor's ACPI device exists (`/sys/bus/acpi/devices/OVTI08F4:00`, status 15)
  but has **no `physical_node`** — it is never instantiated as an I²C client.
- `/sys/bus/acpi/devices/INTC10E0:00` exists and no driver binds to it.
- All the right modules are loaded (`intel_ipu6_isys`, `usbio`, `gpio_usbio`,
  `i2c_usbio`, `intel_skl_int3472_discrete`, `ov08x40`) — and it still doesn't work.

## Root cause

On these platforms the camera sensor (e.g. OmniVision OV08X40, ACPI HID
`OVTI08F4`) lists the **Intel CVS aggregator `INTC10E0`** in its ACPI `_DEP`
(dependencies). The Linux kernel *honors* this dependency — `INTC10E0` is in
`acpi_honor_dep_ids` in `drivers/acpi/scan.c`, annotated:

```
"INTC10E0", /* CVS (ARL) driver must be loaded to allow camera streaming */
```

Enumeration of the sensor is deferred until an `INTC10E0` driver calls
`acpi_dev_clear_dependencies()`. **No such driver exists in mainline Linux**
(Intel's out-of-tree [`vision-drivers`](https://github.com/intel/vision-drivers)
`intel_cvs` only supports Lunar Lake via the LJCA bridge). So the sensor waits
forever, never becomes an I²C client, and the camera stack never assembles.

This module performs exactly the one call the missing driver would make: it
clears the ACPI dependency on `INTC10E0`, letting the ACPI core enumerate the
sensor. Everything downstream (int3472 power/GPIO plumbing, `ov08x40`,
`ipu-bridge`, IPU6) already exists in recent kernels and takes over from there.

## Requirements

- A kernel with the full in-tree stack: IPU6, USBIO (`usbio`, `gpio-usbio`,
  `i2c-usbio` — mainline since 6.18), `intel_skl_int3472`, and your sensor's
  driver (e.g. `ov08x40`). On Ubuntu with an older kernel, install
  `linux-modules-usbio-generic` / `linux-modules-ipu6-generic`.
- Kernel headers and build tools: `sudo apt install build-essential linux-headers-$(uname -r)`
- For the camera to actually stream you also want `libcamera` /
  `pipewire-libcamera` (GNOME/Firefox consume it via PipeWire).

## Install

### Quick test (nothing persistent)

```bash
make
sudo insmod cvs_dep_clear.ko
# wait a few seconds, then:
ls /sys/bus/i2c/devices/ | grep -i ovti   # sensor i2c client should appear
cam -l                                    # camera should be listed
```

A reboot removes it. If it works, make it permanent:

### Permanent (DKMS — survives kernel updates)

```bash
sudo ./install.sh
```

This registers the module with DKMS and loads it at boot via
`/etc/modules-load.d/cvs-dep-clear.conf`. Load order doesn't matter: the ACPI
dependency count only reaches zero once *all* suppliers are ready, so the sensor
enumerates only when int3472/USBIO have also done their part.

### Uninstall

```bash
sudo ./uninstall.sh
```

## Verified working on

| Machine | SoC | Kernel | Sensor | Status |
|---|---|---|---|---|
| Lenovo ThinkPad X1 Carbon Gen 13 (21NX) | Core Ultra 7 255U (ARL-U) | 7.0.0-22 (Ubuntu) | OV08X40 | *testing in progress* |

PRs welcome to extend this table.

## Limitations

- **This does not implement the CVS protocol.** The CVS chip is an always-on
  vision co-processor that shares the sensor with the host. This module only
  tells the kernel "stop waiting for a CVS driver" — it does not perform the
  CVS↔host ownership handshake. On machines where the CVS chip holds the sensor
  at power-on, sensor I²C access may still fail (typically an `ov08x40` chip-ID
  read error in dmesg). Please open an issue with your dmesg if you hit this.
- Any CVS-dependent features (Windows Studio Effects-style presence detection,
  etc.) will not work — but they never do on Linux today anyway.
- Not a substitute for a real driver. Watch these for upstream progress:
  - [intel/ipu6-drivers#281](https://github.com/intel/ipu6-drivers/issues/281) —
    INT3472 GPIO type 0x12 / Lattice MIPI aggregator support
  - [intel/ipu6-drivers#373](https://github.com/intel/ipu6-drivers/issues/373)
  - [intel/vision-drivers](https://github.com/intel/vision-drivers) — Intel's
    out-of-tree `intel_cvs` (LNL-only at time of writing)

## How it works (30 seconds)

```c
adev = acpi_dev_get_first_match_dev("INTC10E0", NULL, -1);
acpi_dev_clear_dependencies(adev);
```

That's the entire mechanism. `acpi_dev_clear_dependencies()` is the exported
kernel API that supplier drivers call to announce "I'm ready"; when the deferred
sensor's unmet-dependency count reaches zero, the ACPI core enumerates it,
i2c-core creates the client on the USBIO I²C bus, and the sensor driver probes.

## License

GPL-2.0 (kernel module requirement, and the right thing anyway).
