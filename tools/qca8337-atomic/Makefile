OPENWRT_DIR ?= ../../../openwrt
OPENWRT_DIR := $(abspath $(OPENWRT_DIR))
KDIR ?= $(OPENWRT_DIR)/build_dir/target-mips_24kc_musl/linux-ath79_generic/linux-6.6.159
KDIR := $(abspath $(KDIR))
TOOLCHAIN_DIR ?= $(OPENWRT_DIR)/staging_dir/toolchain-mips_24kc_gcc-13.3.0_musl/bin
TOOLCHAIN_DIR := $(abspath $(TOOLCHAIN_DIR))
STAGING_DIR ?= $(OPENWRT_DIR)/staging_dir/target-mips_24kc_musl
export STAGING_DIR
CROSS_COMPILE ?= $(TOOLCHAIN_DIR)/mips-openwrt-linux-musl-
TARGET_CC ?= $(TOOLCHAIN_DIR)/mips-openwrt-linux-musl-gcc
BUILD_DIR := build

.PHONY: all module cli

all: module cli

module:
	mkdir -p "$(BUILD_DIR)"
	cp Kbuild "$(BUILD_DIR)/Makefile"
	cp qca8337_atomic.c qca8337_atomic.h "$(BUILD_DIR)/"
	$(MAKE) -C "$(KDIR)" M="$(CURDIR)/$(BUILD_DIR)" ARCH=mips CROSS_COMPILE="$(CROSS_COMPILE)" modules

cli:
	mkdir -p "$(BUILD_DIR)"
	$(TARGET_CC) -Os -Wall -Wextra -Werror -I. qca8337-atomic.c -o "$(BUILD_DIR)/qca8337-atomic"
