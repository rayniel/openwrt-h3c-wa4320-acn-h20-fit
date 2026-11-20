#!/usr/bin/env python3
"""Extract the ART (calibration) partition from a stock H3C WA4320-ACN-H20-FIT
SPI flash dump (e.g. W25Q128FV@SOIC8-h3c-h2.0.BIN) and write it as a 64KB art.bin
laid out for the 0xff0000 partition used by this port.

Usage:
    python extract_art.py <flash_dump.bin> [art.bin] [--mac 74:85:C4:64:01:40]

The stock layout keeps ART at 0xE0000. Without --mac the stock bytes are kept
untouched; the stock image has 0xFF at offset 0, so --mac is needed to provide
the base MAC (written as 3 consecutive MACs: +0, +1, +2 at ART 0x0/0x6/0xc,
QSDK style; OpenWrt only reads the first).
"""
import argparse
import re
import sys

ART_OFFSET = 0xE0000
ART_SIZE = 0x10000


def parse_mac(s):
    if not re.fullmatch(r"[0-9a-fA-F]{2}([:-][0-9a-fA-F]{2}){5}", s):
        raise argparse.ArgumentTypeError("invalid MAC: %s" % s)
    return bytes(int(x, 16) for x in re.split("[:-]", s))


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dump")
    p.add_argument("out", nargs="?", default="art.bin")
    p.add_argument("--mac", type=parse_mac, help="base MAC to write into ART 0x0/0x6/0xc")
    p.add_argument("--offset", type=lambda x: int(x, 0), default=ART_OFFSET,
                   help="ART offset in the dump (default 0xE0000)")
    args = p.parse_args()

    with open(args.dump, "rb") as f:
        data = f.read()
    if len(data) < args.offset + ART_SIZE:
        sys.exit("dump too small (%d bytes)" % len(data))

    art = bytearray(data[args.offset:args.offset + ART_SIZE])

    # 2.4G cal data (AR9300 EEPROM) starts at 0x1000 with header 0x02 0x02;
    # 5G cal data (QCA9888) lives at 0x5000.
    if art[0x1000:0x1002] != b"\x02\x02" or art[0x5000:0x5400] == b"\xff" * 0x400:
        sys.exit("ART signature check failed; wrong dump or --offset")

    if args.mac:
        base = int.from_bytes(args.mac, "big")
        for i in range(3):
            art[i * 6:i * 6 + 6] = (base + i).to_bytes(6, "big")

    with open(args.out, "wb") as f:
        f.write(art)
    print("wrote %s (%d bytes), MAC@0x0: %s" % (
        args.out, len(art),
        ":".join("%02x" % b for b in art[:6]) if art[:6] != b"\xff" * 6 else "unset"))


if __name__ == "__main__":
    main()
