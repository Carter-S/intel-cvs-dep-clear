# Patched kernel modules for camera recovery after suspend/USB re-enumeration.
# GPL-2.0, based on the Ubuntu kernel sources matching the running kernel.
KDIR ?= /lib/modules/$(shell uname -r)/build
MODDIR = /usr/local/lib/camera-recovery/$(shell uname -r)

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/int3472 modules
	$(MAKE) -C $(KDIR) M=$(CURDIR)/ipu-bridge modules

install: all
	install -d $(MODDIR)
	install -m 644 int3472/intel_skl_int3472_common.ko $(MODDIR)/
	install -m 644 int3472/intel_skl_int3472_discrete.ko $(MODDIR)/
	install -m 644 ipu-bridge/ipu-bridge.ko $(MODDIR)/
	install -m 755 camera-recover /usr/local/bin/camera-recover
	install -m 755 99-camera-recover /usr/lib/systemd/system-sleep/99-camera-recover

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/int3472 clean
	$(MAKE) -C $(KDIR) M=$(CURDIR)/ipu-bridge clean
