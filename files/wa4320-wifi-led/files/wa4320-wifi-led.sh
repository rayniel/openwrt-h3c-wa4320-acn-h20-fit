#!/bin/sh

led=/sys/class/leds/green:wlan
state=
reported_error=

log_error() {
	logger -t wa4320-wifi-led "$1"
}

led_off() {
	printf 'none\n' > "$led/trigger" &&
		printf '0\n' > "$led/brightness"
}

cleanup() {
	led_off || log_error "failed to turn WiFi LED off"
}

trap 'exit 0' INT TERM
trap cleanup EXIT

while :; do
	error=
	if ! status="$(ubus call network.wireless status)"; then
		error="failed to read wireless status"
	elif ! devices="$(printf '%s' "$status" | jsonfilter -e '@.*')"; then
		if ! root="$(printf '%s' "$status" | jsonfilter -e '@')"; then
			error="failed to parse wireless status"
		else
			case "$root" in
			'{}'|'{ }') radios= ;;
			*) error="wireless status has no radio states" ;;
			esac
		fi
	elif ! radios="$(printf '%s' "$status" | jsonfilter -e '@.*.up')"; then
		error="wireless status has no radio states"
	else
		device_count="$(printf '%s\n' "$devices" | wc -l)"
		radio_count=0
		for radio in $radios; do
			radio_count=$((radio_count + 1))
		done
		if [ "$device_count" -ne "$radio_count" ]; then
			error="wireless status has missing radio states"
		fi
	fi

	if [ -z "$error" ]; then
		next=off
		for radio in $radios; do
			case "$radio" in
			true) next=blink ;;
			false) ;;
			*) error="invalid wireless status: $radio"; break ;;
			esac
		done
	fi

	if [ -n "$error" ]; then
		if [ "$reported_error" != "$error" ]; then
			log_error "$error"
			reported_error="$error"
		fi
	elif [ "$next" != "$state" ]; then
		reported_error=
		case "$next" in
		blink)
			if ! { printf 'timer\n' > "$led/trigger" &&
				printf '500\n' > "$led/delay_on" &&
				printf '500\n' > "$led/delay_off"; }; then
				log_error "failed to set WiFi LED timer"
				exit 1
			fi
			;;
		off)
			if ! led_off; then
				log_error "failed to turn WiFi LED off"
				exit 1
			fi
			;;
		esac
		state="$next"
	else
		reported_error=
	fi
	sleep 2
done
