#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
BASH = os.environ.get("BASH", "bash")


def shell_path(path):
    path = Path(path).resolve().as_posix()
    if os.name == "nt":
        return "/" + path[0].lower() + path[2:]
    return path


def test_led_states(temp):
    led = temp / "led"
    commands = temp / "bin"
    led.mkdir()
    commands.mkdir()
    for name in ("trigger", "brightness", "delay_on", "delay_off"):
        (led / name).write_text("")
    (temp / "step").write_text("0")
    (commands / "ubus").write_text("""#!/bin/sh
step="$(cat "$TEST_TMP/step")"
case "$step" in
0) printf 'false\\nfalse\\n' ;;
1) printf 'true\\nfalse\\n' ;;
2) printf 'false\\ntrue\\n' ;;
3) exit 1 ;;
4) printf 'true\\nfalse\\n' ;;
5) printf 'BAD\\n' ;;
6) printf 'EMPTY\\n' ;;
7) printf 'false\\nfalse\\n' ;;
8) printf 'true\\ntrue\\n' ;;
9) printf 'false\\nfalse\\n' ;;
10) printf 'invalid\\n' ;;
11) printf 'MISSING\\n' ;;
*) exit 1 ;;
esac
""")
    (commands / "jsonfilter").write_text("""#!/bin/sh
value="$(cat)"
case "$value" in
BAD) exit 1 ;;
EMPTY)
  if [ "$2" = '@' ]; then printf '{ }\\n'; else exit 1; fi ;;
MISSING)
  if [ "$2" = '@.*' ]; then printf 'one\\ntwo\\n'; else printf 'false\\n'; fi ;;
*) printf '%s\\n' "$value" ;;
esac
""")
    (commands / "logger").write_text("""#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_TMP/log"
""")
    (commands / "sleep").write_text("""#!/bin/sh
step="$(cat "$TEST_TMP/step")"
printf '%s:%s:%s:%s\\n' "$step" "$(cat "$TEST_LED/trigger")" \\
  "$(cat "$TEST_LED/delay_on")" "$(cat "$TEST_LED/delay_off")" >> "$TEST_TMP/out"
step=$((step + 1))
printf '%s\\n' "$step" > "$TEST_TMP/step"
if [ "$step" -ge 12 ]; then kill -TERM "$PPID"; fi
""")
    script = temp / "wifi-led.sh"
    original = (ROOT / "files/wa4320-wifi-led/files/wa4320-wifi-led.sh").read_text()
    script.write_text(original.replace("led=/sys/class/leds/green:wlan", 'led="$TEST_LED"'))
    env = os.environ.copy()
    env.update(TEST_TMP=shell_path(temp), TEST_LED=shell_path(led),
               TEST_BIN=shell_path(commands), TEST_SCRIPT=shell_path(script))
    subprocess.run(
        [BASH, "-c", 'chmod +x "$TEST_BIN/"*; PATH="$TEST_BIN:/usr/bin:/bin"; '
                     'export PATH; exec sh "$TEST_SCRIPT"'],
        env=env, check=True, timeout=30,
    )
    expected = [
        "0:none::", "1:timer:500:500", "2:timer:500:500",
        "3:timer:500:500", "4:timer:500:500", "5:timer:500:500",
        "6:none:500:500", "7:none:500:500", "8:timer:500:500",
        "9:none:500:500", "10:none:500:500", "11:none:500:500",
    ]
    assert (temp / "out").read_text().splitlines() == expected
    assert (led / "trigger").read_text().strip() == "none"
    assert (led / "brightness").read_text().strip() == "0"
    log = (temp / "log").read_text()
    assert "failed to read wireless status" in log
    assert "failed to parse wireless status" in log
    assert "invalid wireless status: invalid" in log
    assert "wireless status has missing radio states" in log


def test_apply(temp):
    tree = temp / "openwrt"
    (tree / "target/linux/ath79/dts").mkdir(parents=True)
    (tree / "target/linux/ath79/image").mkdir(parents=True)
    (tree / "target/linux/ath79/generic/base-files/etc/board.d").mkdir(parents=True)
    (tree / "target/linux/ath79/generic/base-files/etc/hotplug.d/firmware").mkdir(parents=True)
    (tree / "package/kernel/mac80211/patches/ath9k").mkdir(parents=True)
    mk = tree / "target/linux/ath79/image/generic.mk"
    mk.write_text("")
    (tree / "target/linux/ath79/generic/base-files/etc/board.d/02_network").write_text(
        'case "$board" in\nexisting,board)\n\t;;\nesac\n')
    (tree / "target/linux/ath79/generic/base-files/etc/hotplug.d/firmware/11-ath10k-caldata").write_text(
        'case "$board" in\n\tdlink,dir-842-c1|\\\n\texisting,board)\n\t;;\nesac\n')
    for _ in range(2):
        subprocess.run([BASH, shell_path(ROOT / "apply.sh"), shell_path(tree), "--no-config"],
                       check=True, timeout=30)
    device = mk.read_text()
    assert device.count("define Device/h3c_wa4320-acn-h20-fit") == 1
    assert device.count("wa4320-wifi-led") == 1
    for name in ("Makefile", "files/wa4320-wifi-led.init", "files/wa4320-wifi-led.sh"):
        assert (tree / "package/wa4320-wifi-led" / name).read_bytes() == (
            ROOT / "files/wa4320-wifi-led" / name).read_bytes()
    dts = tree / "target/linux/ath79/dts/qca9563_h3c_wa4320-acn-h20-fit.dts"
    original_dts = (ROOT / "files/qca9563_h3c_wa4320-acn-h20-fit.dts").read_bytes()
    assert dts.read_bytes() == original_dts
    addition = (b'\n&usb_phy1 {\n\tstatus = "okay";\n};\n'
                b'\n&usb1 {\n\tstatus = "okay";\n};\n')
    for _ in range(2):
        subprocess.run([BASH, shell_path(ROOT / "apply.sh"), shell_path(tree),
                        "--no-config", "--test-usb1"], check=True, timeout=30)
        assert dts.read_bytes() == original_dts + addition
    subprocess.run([BASH, shell_path(ROOT / "apply.sh"), shell_path(tree), "--no-config"],
                   check=True, timeout=30)
    assert dts.read_bytes() == original_dts


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        temp = Path(directory)
        test_led_states(temp)
        test_apply(temp)
    print("WiFi LED behavior and source-tree integration: PASS")
