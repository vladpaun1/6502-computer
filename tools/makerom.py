#!/usr/bin/env python3
# tools/makerom.py
from pathlib import Path
import argparse

def write_vector(rom: bytearray, base_addr: int, vector_addr: int, target: int):
    """
    Write a 16-bit little-endian vector into the ROM.
    base_addr   = CPU address where this ROM is mapped (default $8000)
    vector_addr = CPU address of the vector (e.g., $FFFC for RESET)
    target      = CPU address to jump to on reset (entry point)
    """
    off = vector_addr - base_addr
    if not (0 <= off + 1 < len(rom)):
        raise ValueError(f"Vector {hex(vector_addr)} not inside ROM mapped at {hex(base_addr)}")
    rom[off]     = target & 0xFF        # low byte
    rom[off + 1] = (target >> 8) & 0xFF # high byte

def main():
    p = argparse.ArgumentParser(description="Make a 32 KiB ROM for a 65C02 system using an AT28C256.")
    p.add_argument("-o", "--out", type=Path, default=Path("software/build/rom.bin"),
                   help="Output file (default: software/build/rom.bin)")
    p.add_argument("--size", type=int, default=32 * 1024,
                   help="ROM size in bytes (default: 32768 for AT28C256)")
    p.add_argument("--fill", type=lambda s: int(s, 0), default=0xEA,
                   help="Fill byte (supports 0x..; default: 0xEA NOP)")
    p.add_argument("--base", type=lambda s: int(s, 0), default=0x8000,
                   help="CPU base address where the ROM is mapped (default: 0x8000)")
    p.add_argument("--entry", type=lambda s: int(s, 0), default=None,
                   help="Reset entry address (CPU address). If omitted, uses 0x8000.")
    args = p.parse_args()

    # --- 1) Your program bytes (edit this list) ---
    code = bytearray([
        # Example: count on the data bus, maybe shit shows up
        0xA9, 0xFF,
        0x8D, 0x03, 0x60,

        0xA9, 0x55,
        0x8D, 0x01, 0x60,

    ])
    # ----------------------------------------------

    # Build ROM: program at start of image; remainder filled with NOP
    if len(code) > args.size:
        raise ValueError("Program longer than ROM size.")
    rom = code + bytearray([args.fill]) * (args.size - len(code))

    # --- 2) Set the reset vector (little-endian) ---
    reset_entry = args.entry if args.entry is not None else 0x8000
    write_vector(rom, base_addr=args.base, vector_addr=0xFFFC, target=reset_entry)

    # (Optional) set NMI/IRQ vectors too — uncomment if you want fixed targets
    # write_vector(rom, args.base, 0xFFFA, 0x8000)  # NMI
    # write_vector(rom, args.base, 0xFFFE, 0x8000)  # IRQ/BRK

    # --- 3) Save ---
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(rom)
    print(f"Wrote {len(rom)} bytes to {args.out} (entry={hex(reset_entry)}, base={hex(args.base)})")

if __name__ == "__main__":
    main()
