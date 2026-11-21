#!/usr/bin/env bash
# Add H3C WA4320-ACN-H20-FIT support to an OpenWrt 24.10 source tree.
# Usage: ./apply.sh /path/to/openwrt [--no-config | --build] [--test-usb1]
set -euo pipefail

SRC="${1:-}"
shift || true
[ -n "$SRC" ] && [ -d "$SRC/target/linux/ath79" ] || {
	echo "usage: $0 /path/to/openwrt-24.10 [--no-config | --build] [--test-usb1]" >&2
	exit 1
}

DO_CONFIG=1
DO_BUILD=0
TEST_USB1=0
for a in "$@"; do
	case "$a" in
	--config) ;; # Kept for older callers; configuration is now the default.
	--no-config) DO_CONFIG=0 ;;
	--build) DO_BUILD=1 ;;
	--test-usb1) TEST_USB1=1 ;;
	*) echo "unknown option: $a" >&2; exit 1 ;;
	esac
done
if [ "$DO_CONFIG" = 0 ] && [ "$DO_BUILD" = 1 ]; then
	echo "--no-config and --build cannot be combined" >&2
	exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$SRC" && pwd)"
BOARD=h3c,wa4320-acn-h20-fit
DEV=h3c_wa4320-acn-h20-fit
DTS=qca9563_h3c_wa4320-acn-h20-fit.dts
MK="$SRC/target/linux/ath79/image/generic.mk"
NET="$SRC/target/linux/ath79/generic/base-files/etc/board.d/02_network"
ATH9K_PATCH=999-ath9k-h3c-wa4320-guard-otp.patch
PATCH_DIR="$SRC/package/kernel/mac80211/patches/ath9k"
DRIVER_PACKAGES="wa4320-wifi-led kmod-ath10k-ct ath10k-firmware-qca9888-ct kmod-usb2 kmod-usb-storage kmod-usb-acm kmod-usb-serial kmod-usb-serial-ch341 kmod-usb-serial-ch348 kmod-usb-serial-cp210x kmod-usb-serial-ftdi kmod-usb-serial-pl2303 kmod-usb-serial-xr_usb_serial_common"

cp "$HERE/files/$DTS" "$SRC/target/linux/ath79/dts/$DTS"
if [ "$TEST_USB1" = 1 ]; then
	cat >>"$SRC/target/linux/ath79/dts/$DTS" <<'EOF'

&usb_phy1 {
	status = "okay";
};

&usb1 {
	status = "okay";
};
EOF
fi
cp "$HERE/files/$ATH9K_PATCH" "$PATCH_DIR/$ATH9K_PATCH"
mkdir -p "$SRC/package/wa4320-wifi-led/files"
cp "$HERE/files/wa4320-wifi-led/Makefile" "$SRC/package/wa4320-wifi-led/Makefile"
cp "$HERE/files/wa4320-wifi-led/files/"* "$SRC/package/wa4320-wifi-led/files/"
rm -f "$PATCH_DIR/999-h3c-wa4320-dc-diagnostic.patch"

if ! grep -q "Device/$DEV\$" "$MK"; then
	cat >>"$MK" <<'EOF'

define Device/h3c_wa4320-acn-h20-fit
  SOC := qca9563
  DEVICE_VENDOR := H3C
  DEVICE_MODEL := WA4320-ACN-H20-FIT
  DEVICE_PACKAGES := nmap tcpdump mtr-nojson iperf3 ethtool bind-dig ip-full
  IMAGE_SIZE := 15744k
endef
TARGET_DEVICES += h3c_wa4320-acn-h20-fit
EOF
fi

awk -v dev="$DEV" -v packages="$DRIVER_PACKAGES" '
	BEGIN { count = split(packages, required, " ") }
	$0 == "define Device/" dev { device = 1 }
	device && $1 == "DEVICE_PACKAGES" {
		for (i = 1; i <= count; i++) {
			if ((" " $0 " ") !~ ("[[:space:]]" required[i] "[[:space:]]"))
				$0 = $0 " " required[i]
		}
	}
	$0 == "endef" { device = 0 }
	{ print }
' "$MK" >"$MK.tmp" && mv "$MK.tmp" "$MK"

if ! grep -q "$BOARD" "$NET"; then
	# insert ahead of the first board case in ath79_setup_interfaces()
	awk -v b="$BOARD" '
		!done && /case "\$board" in/ {
			print
			print "\t" b ")"
			print "\t\tucidef_add_switch \"switch0\" \\"
			print "\t\t\t\"0@eth0\" \"5:lan:1\" \"4:lan:2\" \"3:lan:3\" \"2:lan:4\" \"1:lan:5\""
			print "\t\t;;"
			done = 1
			next
		}
		{ print }
	' "$NET" >"$NET.tmp" && mv "$NET.tmp" "$NET"
	chmod +x "$NET"
fi

CAL="$SRC/target/linux/ath79/generic/base-files/etc/hotplug.d/firmware/11-ath10k-caldata"
if ! grep -q "$BOARD" "$CAL"; then
	# QCA9888 board data comes from ART 0x5000; MAC = ART base MAC + 2
	awk -v b="$BOARD" '
		!done && /dlink,dir-842-c1\|\\/ {
			print "\t" b ")"
			print "\t\tcaldata_extract \"art\" 0x5000 0x2f20"
			print "\t\tath10k_patch_mac $(macaddr_add $(mtd_get_mac_binary art 0x0) 2)"
			print "\t\tln -sf /lib/firmware/ath10k/pre-cal-pci-0000\\:00\\:00.0.bin \\"
			print "\t\t\t/lib/firmware/ath10k/QCA9888/hw2.0/board.bin"
			print "\t\t;;"
			done = 1
		}
		{ print }
	' "$CAL" >"$CAL.tmp" && mv "$CAL.tmp" "$CAL"
	chmod +x "$CAL"
fi
if ! grep -Fqx "$(printf '\t%s)' "$BOARD")" "$CAL"; then
	echo "Failed to install QCA9888 ART calibration hook in $CAL" >&2
	exit 1
fi

echo "patched $SRC"

if [ "$DO_CONFIG" = 1 ]; then
	cat >"$SRC/.config" <<EOF
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_$DEV=y
CONFIG_TARGET_MULTI_PROFILE=n
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_PACKAGE_luci=y
EOF
	if [ -n "${EXTRA_CONFIG:-}" ]; then
		printf '%b\n' "$EXTRA_CONFIG" >>"$SRC/.config"
	fi
	make -C "$SRC" defconfig
fi

if [ "$DO_BUILD" = 1 ]; then
	make -C "$SRC" download
	make -C "$SRC" -j"$(nproc)" V=s
	echo "images: $SRC/bin/targets/ath79/generic/"
fi
