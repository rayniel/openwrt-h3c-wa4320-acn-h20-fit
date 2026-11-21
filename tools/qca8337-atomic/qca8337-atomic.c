#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "qca8337_atomic.h"

#define DEVICE_PATH "/dev/qca8337-atomic"

static void usage(const char *program)
{
	fprintf(stderr,
		"Usage:\n"
		"  %s read <register>\n"
		"  %s write <LED_CTRL register> <value>\n"
		"Registers and values accept decimal or 0x-prefixed hex.\n"
		"Write is restricted by the kernel module to LED_CTRL0-3.\n",
		program, program);
}

static int parse_u32(const char *text, uint32_t *value)
{
	char *end;
	unsigned long long parsed;

	errno = 0;
	parsed = strtoull(text, &end, 0);
	if (errno || end == text || *end != '\0' || parsed > UINT32_MAX)
		return -1;

	*value = (uint32_t)parsed;
	return 0;
}

static int open_device(void)
{
	int fd = open(DEVICE_PATH, O_RDWR | O_CLOEXEC);

	if (fd < 0)
		fprintf(stderr, "%s: %s\n", DEVICE_PATH, strerror(errno));
	return fd;
}

int main(int argc, char **argv)
{
	struct qca8337_atomic_reg request = { 0 };
	uint32_t value;
	int fd, ret;

	if (argc == 3 && strcmp(argv[1], "read") == 0) {
		if (parse_u32(argv[2], &request.reg)) {
			usage(argv[0]);
			return EXIT_FAILURE;
		}

		fd = open_device();
		if (fd < 0)
			return EXIT_FAILURE;

		ret = ioctl(fd, QCA8337_ATOMIC_READ, &request);
		if (ret < 0)
			fprintf(stderr, "read 0x%08" PRIx32 ": %s\n",
				request.reg, strerror(errno));
		else
			printf("0x%08" PRIx32 " = 0x%08" PRIx32 "\n",
			       request.reg, request.value);
		close(fd);
		return ret < 0 ? EXIT_FAILURE : EXIT_SUCCESS;
	}

	if (argc == 4 && strcmp(argv[1], "write") == 0) {
		if (parse_u32(argv[2], &request.reg) ||
		    parse_u32(argv[3], &value)) {
			usage(argv[0]);
			return EXIT_FAILURE;
		}
		request.value = value;

		fd = open_device();
		if (fd < 0)
			return EXIT_FAILURE;

		ret = ioctl(fd, QCA8337_ATOMIC_WRITE, &request);
		if (ret < 0) {
			fprintf(stderr, "write 0x%08" PRIx32 ": %s\n",
				request.reg, strerror(errno));
			close(fd);
			return EXIT_FAILURE;
		}

		ret = ioctl(fd, QCA8337_ATOMIC_READ, &request);
		if (ret < 0)
			fprintf(stderr, "write issued; readback failed: %s\n",
				strerror(errno));
		else if (request.value != value) {
			fprintf(stderr,
				"readback mismatch at 0x%08" PRIx32
				": expected 0x%08" PRIx32
				", got 0x%08" PRIx32 "\n",
				request.reg, value, request.value);
			ret = -1;
		} else {
			printf("0x%08" PRIx32 " = 0x%08" PRIx32 "\n",
			       request.reg, request.value);
		}

		close(fd);
		return ret < 0 ? EXIT_FAILURE : EXIT_SUCCESS;
	}

	usage(argv[0]);
	return EXIT_FAILURE;
}
