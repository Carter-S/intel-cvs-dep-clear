// SPDX-License-Identifier: GPL-2.0
/*
 * cvs_dep_clear - unblock camera sensor enumeration on Arrow Lake CVS platforms
 *
 * On Lenovo ThinkPad X1 Carbon Gen 13 (Arrow Lake-U) the OVTI08F4 (ov08x40)
 * camera sensor lists the INTC10E0 CVS aggregator in its ACPI _DEP. INTC10E0
 * is in the kernel's acpi_honor_dep_ids ("CVS (ARL) driver must be loaded to
 * allow camera streaming"), so the sensor's enumeration is deferred until an
 * INTC10E0 driver calls acpi_dev_clear_dependencies(). No such driver exists
 * in mainline as of 7.0, so the sensor never becomes an i2c client.
 *
 * This module performs exactly that one call, standing in for the missing
 * CVS driver's "ready" notification. On success the ACPI core asynchronously
 * enumerates the deferred sensor, i2c-core creates the i2c client on the
 * USBIO bus, and ov08x40 probes.
 *
 * Runtime-only; no persistent state. Reboot reverts everything.
 */
#include <linux/module.h>
#include <linux/acpi.h>

static int __init cvs_dep_clear_init(void)
{
	struct acpi_device *adev;

	adev = acpi_dev_get_first_match_dev("INTC10E0", NULL, -1);
	if (!adev) {
		pr_err("cvs_dep_clear: no INTC10E0 ACPI device found\n");
		return -ENODEV;
	}

	pr_info("cvs_dep_clear: clearing ACPI _DEP on %s\n",
		acpi_dev_name(adev));
	acpi_dev_clear_dependencies(adev);
	acpi_dev_put(adev);

	pr_info("cvs_dep_clear: done - deferred consumers will now enumerate\n");
	return 0;
}

static void __exit cvs_dep_clear_exit(void)
{
}

module_init(cvs_dep_clear_init);
module_exit(cvs_dep_clear_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Carter-S");
MODULE_DESCRIPTION("Clear ACPI _DEP on INTC10E0 CVS aggregator to unblock camera sensor enumeration");
