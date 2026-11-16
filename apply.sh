#!/usr/bin/env bash
# Add H3C WA4320-ACN-H20-FIT support to an OpenWrt 24.10 source tree.
# Usage: ./apply.sh /path/to/openwrt [--config] [--build]
#   --config  write a minimal .config (ath79/generic + this device) and run defconfig
#   --build   implies --config, then run "make download" and "make -jN"
set -euo pipefail

SRC="${1:-}"
shift || true
[ -n "$SRC" ] && [ -d "$SRC/target/linux/ath79" ] || {
	echo "usage: $0 /path/to/openwrt-24.10 [--config] [--build]" >&2
	exit 1
}

DO_CONFIG=0
DO_BUILD=0
for a in "$@"; do
	case "$a" in
	--config) DO_CONFIG=1 ;;
	--build) DO_CONFIG=1; DO_BUILD=1 ;;
	*) echo "unknown option: $a" >&2; exit 1 ;;
	esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$SRC" && pwd)"
BOARD=h3c,wa4320-acn-h20-fit
DEV=h3c_wa4320-acn-h20-fit
DTS=qca9563_h3c_wa4320-acn-h20-fit.dts
MK="$SRC/target/linux/ath79/image/generic.mk"
NET="$SRC/target/linux/ath79/generic/base-files/etc/board.d/02_network"

cp "$HERE/files/$DTS" "$SRC/target/linux/ath79/dts/$DTS"

if ! grep -q "Device/$DEV\$" "$MK"; then
	cat >>"$MK" <<'EOF'

define Device/h3c_wa4320-acn-h20-fit
  SOC := qca9563
  DEVICE_VENDOR := H3C
  DEVICE_MODEL := WA4320-ACN-H20-FIT
  DEVICE_PACKAGES := kmod-ath10k-ct ath10k-firmware-qca988x-ct kmod-usb2
  IMAGE_SIZE := 15360k
endef
TARGET_DEVICES += h3c_wa4320-acn-h20-fit
EOF
fi

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

echo "patched $SRC"

if [ "$DO_CONFIG" = 1 ]; then
	cat >"$SRC/.config" <<EOF
CONFIG_TARGET_ath79=y
CONFIG_TARGET_ath79_generic=y
CONFIG_TARGET_ath79_generic_DEVICE_$DEV=y
CONFIG_TARGET_MULTI_PROFILE=n
CONFIG_PACKAGE_luci=y
EOF
	make -C "$SRC" defconfig
fi

if [ "$DO_BUILD" = 1 ]; then
	make -C "$SRC" download
	make -C "$SRC" -j"$(nproc)" V=s
	echo "images: $SRC/bin/targets/ath79/generic/"
fi
