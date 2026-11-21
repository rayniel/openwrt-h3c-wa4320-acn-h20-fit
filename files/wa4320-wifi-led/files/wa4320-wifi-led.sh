#!/bin/sh

led=/sys/class/leds/green:wlan
net_dir=/sys/class/net
uptime_file=/proc/uptime
state=
delay=
reported_error=
previous_interfaces=
previous_total=
previous_time=

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

sample_traffic() {
	local iface rx tx uptime seconds fraction

	sample_interfaces=
	sample_total=0
	if [ ! -d "$net_dir" ]; then
		error="wireless interface directory is unavailable"
		return 1
	fi
	for iface in "$net_dir"/*; do
		[ -d "$iface/phy80211" ] || continue
		if ! read -r rx < "$iface/statistics/rx_bytes" ||
			! read -r tx < "$iface/statistics/tx_bytes"; then
			error="failed to read WiFi counters for ${iface##*/}"
			return 1
		fi
		case "$rx:$tx" in
		:*|*:|*[!0-9:]*) error="invalid WiFi counters for ${iface##*/}"; return 1 ;;
		esac
		sample_interfaces="$sample_interfaces ${iface##*/}"
		sample_total=$((sample_total + rx + tx))
		if [ "$sample_total" -lt 0 ]; then
			error="WiFi counter overflow"
			return 1
		fi
	done

	if ! read -r uptime _ < "$uptime_file"; then
		error="failed to read uptime"
		return 1
	fi
	case "$uptime" in
	*.*) seconds="${uptime%.*}"; fraction="${uptime#*.}" ;;
	*) error="invalid uptime"; return 1 ;;
	esac
	case "$seconds" in
	''|*[!0-9]*) error="invalid uptime"; return 1 ;;
	esac
	case "$fraction" in
	[0-9][0-9]) ;;
	*) error="invalid uptime"; return 1 ;;
	esac
	sample_time=$((seconds * 100 + 1$fraction - 100))
}

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

	if [ -z "$error" ] && [ "$next" = blink ]; then
		next_delay=500
		if sample_traffic; then
			if [ -n "$previous_time" ] &&
				[ "$sample_interfaces" = "$previous_interfaces" ] &&
				[ "$sample_total" -ge "$previous_total" ] &&
				[ "$sample_time" -gt "$previous_time" ]; then
				elapsed=$((sample_time - previous_time))
				delta=$((sample_total - previous_total))
				rate=$((delta / elapsed * 100 + delta % elapsed * 100 / elapsed))
				if [ "$rate" -ge 33554432 ]; then
					next_delay=40
				elif [ "$rate" -ge 8388608 ]; then
					next_delay=60
				elif [ "$rate" -ge 2097152 ]; then
					next_delay=100
				elif [ "$rate" -ge 524288 ]; then
					next_delay=150
				elif [ "$rate" -ge 131072 ]; then
					next_delay=250
				elif [ "$rate" -ge 16384 ]; then
					next_delay=350
				fi
			fi
			previous_interfaces="$sample_interfaces"
			previous_total="$sample_total"
			previous_time="$sample_time"
		fi
	elif [ -z "$error" ]; then
		previous_interfaces=
		previous_total=
		previous_time=
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
				printf '%s\n' "$next_delay" > "$led/delay_on" &&
				printf '%s\n' "$next_delay" > "$led/delay_off"; }; then
				log_error "failed to set WiFi LED timer"
				exit 1
			fi
			delay="$next_delay"
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
		if [ "$next" = blink ] && [ "$next_delay" != "$delay" ]; then
			if ! { printf '%s\n' "$next_delay" > "$led/delay_on" &&
				printf '%s\n' "$next_delay" > "$led/delay_off"; }; then
				log_error "failed to update WiFi LED timer"
				exit 1
			fi
			delay="$next_delay"
		fi
	fi
	sleep 2
done
