# Atomic QCA8337 MDIO test tool

This temporary tool accesses the QCA8337 through the registered MDIO bus.
Each 32-bit switch-register transaction holds `mdio_lock` across page
selection, the driver's 5 microsecond page-switch delay, and data access.
The sequence and low-half-first transfer order match the OpenWrt 24.10
`ar8216` driver for the ath79 target.

The module identifies the switch by reading CTRL and refuses to attach unless
the version is QCA8337. Reads are limited to aligned addresses in the
17-bit switch-register window (`0x0000` through `0x1fffc`). Writes are
restricted in the kernel to LED_CTRL0-3 (`0x50`, `0x54`, `0x58`, `0x5c`).
The device node is mode `0600`, and ioctls additionally require
`CAP_SYS_RAWIO`.

## Build

From this directory, with the prepared WA4320 OpenWrt build tree alongside the
adaptation project:

```sh
make
```

This builds `build/qca8337_atomic.ko` and the MIPS `build/qca8337-atomic`
client against the local OpenWrt 24.10 kernel build tree and toolchain. The
module must match the kernel actually running on the AP; matching only the
kernel version string is not sufficient.

## Use on the AP

Transfer both build outputs to a temporary directory on the AP. Keep the
serial recovery path available. Load the module explicitly; it is not
configured to autoload:

```sh
insmod ./qca8337_atomic.ko
./qca8337-atomic read 0x00
./qca8337-atomic read 0x50
./qca8337-atomic read 0x54
./qca8337-atomic read 0x58
./qca8337-atomic read 0x5c
```

Start with reads only and record the original LED register values. A write
changes one complete LED control register and prints a readback; use it only
after identifying the intended LED field, and restore the recorded value
immediately after the test. Do not write other switch registers, alter VLAN,
SGMII, strap, flash, or ART settings, or reboot as part of this test.
If a write reports an error, inspect the register before continuing; a bus
failure during the two-half transfer can leave a partial value.

Remove the temporary module when finished:

```sh
rmmod qca8337_atomic
```

The module is built for testing and is not included in the firmware image.
