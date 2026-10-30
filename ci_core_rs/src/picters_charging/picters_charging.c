// SPDX-License-Identifier: GPL-2.0
/* Picters charging targets: independent, leased MCA minimum-election votes. */
#include <linux/err.h>
#include <linux/jiffies.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/power_supply.h>
#include <linux/sysfs.h>
#include <linux/workqueue.h>
#include "mca_vendor_abi.h"

/* Direct imports from the captured vendor ABI, with its real symbol CRCs.
 * No private structure access, symbol lookup tricks or CFI exceptions.
 */

#define PICTERS_CLIENT "picters_charging"
#define PICTERS_LEASE (30 * HZ)

static DEFINE_MUTEX(charging_lock);
static struct kobject *charging_kobj;
static struct delayed_work charging_work;
static const char * const slot_names[] = {
	"buck_input", "single_chg_cur", "multi_chg_cur",
};
static bool owned[ARRAY_SIZE(slot_names)];
static unsigned int requested_w;
static unsigned long lease_until;
static int input_ma, battery_ma, last_error;
static bool stopping;

static bool needs_tick(void)
{
	return requested_w || owned[0] || owned[1] || owned[2];
}

static int release_locked(void)
{
	struct mca_votable *slot;
	int i, ret, error = 0;

	for (i = 0; i < ARRAY_SIZE(slot_names); i++) {
		if (!owned[i])
			continue;
		slot = mca_find_votable(slot_names[i]);
		if (IS_ERR_OR_NULL(slot)) {
			error = -ENODEV;
			continue;
		}
		/* Disabling the own vote restores the election of the other clients. */
		ret = mca_vote(slot, PICTERS_CLIENT, false, 0);
		if (ret < 0)
			error = ret;
		else
			owned[i] = false;
	}
	if (!error) {
		input_ma = 0;
		battery_ma = 0;
	}
	return error;
}

static int property(const char *name, enum power_supply_property prop, int *out)
{
	struct power_supply *supply;
	union power_supply_propval value;
	int ret;

	supply = power_supply_get_by_name(name);
	if (!supply)
		return -ENODEV;
	ret = power_supply_get_property(supply, prop, &value);
	power_supply_put(supply);
	if (!ret)
		*out = value.intval;
	return ret;
}

static int apply_locked(void)
{
	struct mca_votable *slots[ARRAY_SIZE(slot_names)];
	int online, bus_uv, cell_uv, in, bat, i, ret;

	if (!requested_w)
		return release_locked();
	ret = property("usb", POWER_SUPPLY_PROP_ONLINE, &online);
	if (ret)
		goto fail;
	if (!online)
		return release_locked(); /* Keep the target pending until wired power. */
	ret = property("usb", POWER_SUPPLY_PROP_VOLTAGE_NOW, &bus_uv);
	if (ret)
		goto fail;
	ret = property("battery", POWER_SUPPLY_PROP_VOLTAGE_NOW, &cell_uv);
	if (ret)
		goto fail;
	/* These units/ranges belong to the captured pudding implementation. */
	if (bus_uv < 4000000 || bus_uv > 24000000 ||
	    cell_uv < 2500000 || cell_uv > 5500000) {
		ret = -ERANGE;
		goto fail;
	}
	in = min_t(u64, div_u64((u64)requested_w * 1000000000ULL,
			       bus_uv), 30000);
	bat = min_t(u64, div_u64((u64)requested_w * 1000000000ULL,
				cell_uv), 30000);
	for (i = 0; i < ARRAY_SIZE(slots); i++) {
		slots[i] = mca_find_votable(slot_names[i]);
		if (IS_ERR_OR_NULL(slots[i])) {
			ret = -ENODEV;
			goto fail;
		}
	}
	for (i = 0; i < ARRAY_SIZE(slots); i++) {
		/* A callback may fail after its vote was registered: still undo it. */
		owned[i] = true;
		ret = mca_vote(slots[i], PICTERS_CLIENT, true, i ? bat : in);
		if (ret < 0)
			goto fail;
	}
	input_ma = in;
	battery_ma = bat;
	return 0;
fail:
	release_locked();
	return ret;
}

static void charging_tick(struct work_struct *work)
{
	mutex_lock(&charging_lock);
	if (stopping) {
		mutex_unlock(&charging_lock);
		return;
	}
	if (requested_w && time_after_eq(jiffies, lease_until))
		requested_w = 0;
	last_error = apply_locked();
	if (needs_tick())
		schedule_delayed_work(&charging_work, 2 * HZ);
	mutex_unlock(&charging_lock);
}

static ssize_t power_target_show(struct kobject *kobj,
				struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%u\n", READ_ONCE(requested_w));
}

static ssize_t power_target_store(struct kobject *kobj,
				 struct kobj_attribute *attr,
				 const char *buf, size_t count)
{
	unsigned int value;
	int ret;

	ret = kstrtouint(buf, 10, &value);
	if (ret || value > 120)
		return -EINVAL;
	mutex_lock(&charging_lock);
	if (stopping) {
		mutex_unlock(&charging_lock);
		return -ENODEV;
	}
	requested_w = value;
	lease_until = jiffies + PICTERS_LEASE;
	ret = apply_locked();
	if (ret)
		requested_w = 0;
	last_error = ret;
	if (needs_tick())
		mod_delayed_work(system_wq, &charging_work, 2 * HZ);
	else
		cancel_delayed_work(&charging_work);
	mutex_unlock(&charging_lock);
	return ret ? ret : count;
}

static ssize_t status_show(struct kobject *kobj,
			   struct kobj_attribute *attr, char *buf)
{
	ssize_t size;

	mutex_lock(&charging_lock);
	size = sysfs_emit(buf, "target_w=%u input_ma=%d battery_ma=%d error=%d\n",
			  requested_w, input_ma, battery_ma, last_error);
	mutex_unlock(&charging_lock);
	return size;
}

static ssize_t capabilities_show(struct kobject *kobj,
				 struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "PMM_MCA_TARGET_V1 leased own_votes\n");
}

static struct kobj_attribute power_target_attr = __ATTR_RW(power_target);
static struct kobj_attribute status_attr = __ATTR_RO(status);
static struct kobj_attribute capabilities_attr = __ATTR_RO(capabilities);
static struct attribute *charging_attrs[] = {
	&power_target_attr.attr, &status_attr.attr, &capabilities_attr.attr, NULL,
};
static const struct attribute_group charging_group = { .attrs = charging_attrs };

static int __init picters_charging_init(void)
{
	int ret;

	INIT_DELAYED_WORK(&charging_work, charging_tick);
	charging_kobj = kobject_create_and_add("picters_charging", kernel_kobj);
	if (!charging_kobj)
		return -ENOMEM;
	ret = sysfs_create_group(charging_kobj, &charging_group);
	if (ret) {
		kobject_put(charging_kobj);
		return ret;
	}
	return 0;
}

static void __exit picters_charging_exit(void)
{
	mutex_lock(&charging_lock);
	stopping = true;
	mutex_unlock(&charging_lock);
	sysfs_remove_group(charging_kobj, &charging_group);
	cancel_delayed_work_sync(&charging_work);
	mutex_lock(&charging_lock);
	requested_w = 0;
	release_locked();
	mutex_unlock(&charging_lock);
	kobject_put(charging_kobj);
}

module_init(picters_charging_init);
module_exit(picters_charging_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Picters");
MODULE_DESCRIPTION("Picters leased charging targets for the pudding MCA ABI");
MODULE_SOFTDEP("pre: mca_voter mca_strategy_buckchg mca_strategy_quickchg");
