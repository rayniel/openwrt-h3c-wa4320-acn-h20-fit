// SPDX-License-Identifier: GPL-2.0-only

#include <linux/capability.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/phy.h>
#include <linux/uaccess.h>

#include "qca8337_atomic.h"

#define QCA8337_REG_MAX		0x1fffc
#define QCA8337_REG_CTRL	0x0000
#define QCA8337_REG_LED_CTRL0	0x0050
#define QCA8337_REG_LED_CTRL1	0x0054
#define QCA8337_REG_LED_CTRL2	0x0058
#define QCA8337_REG_LED_CTRL3	0x005c
#define QCA8337_MDIO_PAGE_PHY	0x18
#define QCA8337_MDIO_REG_PHY	0x10
#define QCA8337_VERSION		0x13

static char *mdio_bus_name = "mdio.0";
module_param(mdio_bus_name, charp, 0444);
MODULE_PARM_DESC(mdio_bus_name, "MDIO bus name (default: mdio.0)");

static struct mii_bus *switch_bus;
static struct miscdevice qca8337_miscdev;

static int qca8337_reg_parts(u32 reg, u16 *r1, u16 *r2, u16 *page)
{
	if (reg > QCA8337_REG_MAX || (reg & 3))
		return -EINVAL;

	reg >>= 1;
	*r1 = reg & 0x1e;
	reg >>= 5;
	*r2 = reg & 0x7;
	reg >>= 3;
	*page = reg & 0x1ff;
	return 0;
}

static int qca8337_read_locked(struct mii_bus *bus, u32 reg, u32 *value)
{
	unsigned long flags;
	u16 r1, r2, page;
	int lo, hi, ret;

	ret = qca8337_reg_parts(reg, &r1, &r2, &page);
	if (ret)
		return ret;

	mutex_lock(&bus->mdio_lock);
	if (READ_ONCE(bus->state) != MDIOBUS_REGISTERED) {
		ret = -ENODEV;
		goto unlock;
	}

	local_irq_save(flags);
	ret = bus->write(bus, QCA8337_MDIO_PAGE_PHY, 0, page);
	if (ret < 0)
		goto restore_irq;

	udelay(5);
	lo = bus->read(bus, QCA8337_MDIO_REG_PHY | r2, r1);
	if (lo < 0) {
		ret = lo;
		goto restore_irq;
	}

	hi = bus->read(bus, QCA8337_MDIO_REG_PHY | r2, r1 + 1);
	if (hi < 0) {
		ret = hi;
		goto restore_irq;
	}

	*value = ((u32)hi << 16) | lo;
	ret = 0;

restore_irq:
	local_irq_restore(flags);
unlock:
	mutex_unlock(&bus->mdio_lock);
	return ret;
}

static int qca8337_write_locked(struct mii_bus *bus, u32 reg, u32 value)
{
	unsigned long flags;
	u16 r1, r2, page;
	int ret;

	if (reg != QCA8337_REG_LED_CTRL0 &&
	    reg != QCA8337_REG_LED_CTRL1 &&
	    reg != QCA8337_REG_LED_CTRL2 &&
	    reg != QCA8337_REG_LED_CTRL3)
		return -EPERM;

	ret = qca8337_reg_parts(reg, &r1, &r2, &page);
	if (ret)
		return ret;

	mutex_lock(&bus->mdio_lock);
	if (READ_ONCE(bus->state) != MDIOBUS_REGISTERED) {
		ret = -ENODEV;
		goto unlock;
	}

	local_irq_save(flags);
	ret = bus->write(bus, QCA8337_MDIO_PAGE_PHY, 0, page);
	if (ret < 0)
		goto restore_irq;

	udelay(5);
	ret = bus->write(bus, QCA8337_MDIO_REG_PHY | r2, r1,
			 value & 0xffff);
	if (ret < 0)
		goto restore_irq;

	ret = bus->write(bus, QCA8337_MDIO_REG_PHY | r2, r1 + 1,
			 value >> 16);

restore_irq:
	local_irq_restore(flags);
unlock:
	mutex_unlock(&bus->mdio_lock);
	return ret < 0 ? ret : 0;
}

static long qca8337_ioctl(struct file *file, unsigned int command,
			  unsigned long argument)
{
	struct qca8337_atomic_reg request;
	void __user *user_request = (void __user *)argument;
	int ret;

	if (!capable(CAP_SYS_RAWIO))
		return -EPERM;

	if (command != QCA8337_ATOMIC_READ &&
	    command != QCA8337_ATOMIC_WRITE)
		return -ENOTTY;

	if (copy_from_user(&request, user_request, sizeof(request)))
		return -EFAULT;

	if (command == QCA8337_ATOMIC_READ) {
		ret = qca8337_read_locked(switch_bus, request.reg,
					  &request.value);
		if (ret)
			return ret;

		return copy_to_user(user_request, &request, sizeof(request)) ?
			-EFAULT : 0;
	}

	return qca8337_write_locked(switch_bus, request.reg, request.value);
}

static const struct file_operations qca8337_fops = {
	.owner = THIS_MODULE,
	.unlocked_ioctl = qca8337_ioctl,
	.llseek = no_llseek,
};

static int __init qca8337_atomic_init(void)
{
	u32 ctrl;
	int ret;

	switch_bus = mdio_find_bus(mdio_bus_name);
	if (!switch_bus) {
		pr_err("qca8337-atomic: MDIO bus '%s' not found\n",
		       mdio_bus_name);
		return -ENODEV;
	}

	if (!switch_bus->read || !switch_bus->write ||
	    READ_ONCE(switch_bus->state) != MDIOBUS_REGISTERED) {
		ret = -ENODEV;
		goto put_bus;
	}

	ret = qca8337_read_locked(switch_bus, QCA8337_REG_CTRL, &ctrl);
	if (ret)
		goto put_bus;

	if (ctrl == U32_MAX || ((ctrl >> 8) & 0xff) != QCA8337_VERSION) {
		pr_err("qca8337-atomic: bus '%s' did not identify a QCA8337 (CTRL=0x%08x)\n",
		       mdio_bus_name, ctrl);
		ret = -ENODEV;
		goto put_bus;
	}

	qca8337_miscdev.minor = MISC_DYNAMIC_MINOR;
	qca8337_miscdev.name = "qca8337-atomic";
	qca8337_miscdev.fops = &qca8337_fops;
	qca8337_miscdev.mode = 0600;
	ret = misc_register(&qca8337_miscdev);
	if (ret)
		goto put_bus;

	pr_info("qca8337-atomic: attached to %s (CTRL=0x%08x)\n",
		mdio_bus_name, ctrl);
	return 0;

put_bus:
	put_device(&switch_bus->dev);
	switch_bus = NULL;
	return ret;
}

static void __exit qca8337_atomic_exit(void)
{
	misc_deregister(&qca8337_miscdev);
	put_device(&switch_bus->dev);
}

module_init(qca8337_atomic_init);
module_exit(qca8337_atomic_exit);

MODULE_DESCRIPTION("Atomic, LED-register-limited QCA8337 MDIO test access");
MODULE_LICENSE("GPL");
