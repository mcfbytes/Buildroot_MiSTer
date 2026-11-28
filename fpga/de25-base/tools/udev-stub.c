// SPDX-License-Identifier: GPL-3.0-or-later
/* A libudev that reports "no udev": FlexLM's host-ID probe then skips its device scan, which
 * aborts in containers (docs/de25-quartus.md §4). udev_new() returning NULL ends the probe. */
#include <stddef.h>
#define NUL(f) void *f(void) { return NULL; }
NUL(udev_new) NUL(udev_unref) NUL(udev_enumerate_new) NUL(udev_enumerate_unref)
NUL(udev_enumerate_get_list_entry) NUL(udev_device_new_from_syspath) NUL(udev_device_unref)
NUL(udev_list_entry_get_next) NUL(udev_list_entry_get_name) NUL(udev_list_entry_get_value)
NUL(udev_device_get_devlinks_list_entry) NUL(udev_device_get_devnode) NUL(udev_device_get_devpath)
NUL(udev_device_get_devtype) NUL(udev_device_get_properties_list_entry) NUL(udev_device_get_subsystem)
NUL(udev_device_get_sysname) NUL(udev_device_get_sysnum) NUL(udev_device_get_syspath)
int udev_enumerate_scan_devices(void) { return -1; }
