#ifndef QCA8337_ATOMIC_H
#define QCA8337_ATOMIC_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define QCA8337_ATOMIC_IOC_MAGIC 0xa7

struct qca8337_atomic_reg {
	__u32 reg;
	__u32 value;
};

#define QCA8337_ATOMIC_READ \
	_IOWR(QCA8337_ATOMIC_IOC_MAGIC, 0, struct qca8337_atomic_reg)
#define QCA8337_ATOMIC_WRITE \
	_IOW(QCA8337_ATOMIC_IOC_MAGIC, 1, struct qca8337_atomic_reg)

#endif
