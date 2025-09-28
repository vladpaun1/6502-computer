#!/usr/bin/env python3
# tools/makerom.py
from pathlib import Path
import argparse

def main():
    p = argparse.ArgumentParser(description="Create a 32 KiB 0xEA-filled ROM image (AT28C256).")
    p.add_argument("-o", "--out", type=Path, default=Path("software/build/rom.bin"),
                   help="Output path for ROM image (default: software/build/rom.bin)")
    p.add_argument("--size", type=int, default=32 * 1024,
                   help="ROM size in bytes (default: 32768 for AT28C256)")
    p.add_argument("--fill", type=lambda s: int(s, 0), default=0xEA,
                   help="Fill byte (int, supports 0x..; default: 0xEA NOP)")
    args = p.parse_args()

    args.out.parent.mkdir(parents=True, exist_ok=True)
    rom = bytearray([args.fill] * args.size)
    args.out.write_bytes(rom)
    print(f"Wrote {len(rom)} bytes to {args.out}")

if __name__ == "__main__":
    main()
