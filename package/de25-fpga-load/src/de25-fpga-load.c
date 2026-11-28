// SPDX-License-Identifier: GPL-2.0-only
/* de25-fpga-load - load a full FPGA image by firmware name through fpga-mgr. */
#include <linux/fpga/fpga-mgr.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/time64.h>
#include <linux/timekeeping.h>

/* stratix10-soc waits this long for the SDM to report completion; 0 fails at once. */
#define DE25_FPGA_COMPLETE_TIMEOUT_US	(30 * USEC_PER_SEC)

static const char * const de25_fpga_mgr_compat = "intel,agilex5-soc-fpga-mgr";

static ssize_t load_store(struct device *dev, struct device_attribute *attr,
			  const char *buf, size_t count)
{
	struct fpga_image_info *info;
	struct fpga_manager *mgr;
	struct device_node *np;
	char *copy, *name;
	ktime_t start;
	int ret;

	copy = kstrndup(buf, count, GFP_KERNEL);
	if (!copy)
		return -ENOMEM;
	name = strim(copy);
	if (!*name || strchr(name, '/')) {
		ret = -EINVAL;
		goto out_copy;
	}

	np = of_find_compatible_node(NULL, NULL, de25_fpga_mgr_compat);
	if (!np) {
		ret = -ENODEV;
		goto out_copy;
	}
	mgr = of_fpga_mgr_get(np);
	of_node_put(np);
	if (IS_ERR(mgr)) {
		ret = PTR_ERR(mgr);
		goto out_copy;
	}

	info = fpga_image_info_alloc(dev);
	if (!info) {
		ret = -ENOMEM;
		goto out_mgr;
	}
	info->firmware_name = devm_kstrdup(dev, name, GFP_KERNEL);
	if (!info->firmware_name) {
		ret = -ENOMEM;
		goto out_info;
	}
	/* Full reconfiguration: no FPGA_MGR_PARTIAL_RECONFIG in info->flags. */
	info->config_complete_timeout_us = DE25_FPGA_COMPLETE_TIMEOUT_US;

	ret = fpga_mgr_lock(mgr);
	if (ret) {
		dev_warn(dev, "%s: a load is already in progress\n", name);
		goto out_info;
	}
	start = ktime_get();
	ret = fpga_mgr_load(mgr, info);
	fpga_mgr_unlock(mgr);
	if (ret)
		dev_err(dev, "%s: load failed (%d)\n", name, ret);
	else
		dev_info(dev, "%s: loaded in %lld ms\n", name,
			 ktime_ms_delta(ktime_get(), start));

out_info:
	fpga_image_info_free(info);
out_mgr:
	fpga_mgr_put(mgr);
out_copy:
	kfree(copy);
	return ret ? ret : count;
}
static DEVICE_ATTR_WO(load);

static struct attribute *de25_fpga_load_attrs[] = {
	&dev_attr_load.attr,
	NULL
};
ATTRIBUTE_GROUPS(de25_fpga_load);

static struct miscdevice de25_fpga_load_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "de25-fpga-load",
	.groups = de25_fpga_load_groups,
};
module_misc_device(de25_fpga_load_misc);

MODULE_DESCRIPTION("DE25-Nano full-bitstream load trigger");
MODULE_LICENSE("GPL");
