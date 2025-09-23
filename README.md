# 6502-OS-Project
A personal project building a 65c02 based 8-bit breadboard computer and coding a lightweight custom OS for it

## Shopping list
### 1. Power and breadboarding
- 5 V regulated power supply — USB → 5 V wall adapter (at least 1 A) is fine.
- Breadboard power module (plugs into the rails, often accepts USB or barrel jack). Choose one that can output 5 V only (many cheap MB102 modules have 3.3 V as well).
- Breadboards — get a few 830-point ones, plus maybe a larger “bus board” with long rails. For bigger builds, you’ll want 3–4 boards linked.
- Jumper wire kit — solid-core, pre-cut is cleaner than floppy dupont wires for logic.
- Male/female pin headers — to adapt things like Raspberry Pi GPIO or USB-serial adapters to the board.

### 2. Clock generation
The W65C02S is static, so you can run it from Hz → 14 MHz.
- Fixed oscillator — e.g. a 14 MHz canned oscillator module (TTL square wave output).
- Variable/slow clock module — e.g. a 555-timer kit, or a debounced pushbutton single-step circuit. Ben Eater sells a neat “step clock” board, but you can DIY with a Schmitt trigger + button.
- Switching between the two: run a selector so you can swap between “slow debug” and “full speed.”

### 3. Memory (RAM + ROM)
The 6502 doesn’t have internal program memory, so you need external RAM and ROM.
#### RAM:
- Typical hobby choice: 32 KB SRAM (e.g. 62256, 55 ns access).
- Faster parts exist (e.g. 15 ns), which you’ll want if running at 14 MHz (see timing below).
#### ROM/EEPROM:
- Common: 28C256 (32 KB parallel EEPROM). Easy to program with a cheap USB programmer (TL866II is the hobbyist standard).
Why needed? Because RAM is volatile — when you power on, it’s empty. You need some non-volatile code (a “monitor” or “bootloader”) so the CPU doesn’t start executing garbage.
Typical memory map: lower half = RAM, upper page(s) = ROM.
### 4. I/O chips
The 6502 doesn’t have built-in GPIO.
- The classic companion is the W65C22 VIA (Versatile Interface Adapter):
  - 2× 8-bit parallel I/O ports (configurable as input/output).
  - Timers, shift register, interrupts.
  - Acts as a “bridge” between CPU and real devices like LEDs, LCDs, keypads, or serial ports.
Why not wire directly? Because peripherals often need latches, timers, or serial shifts — the VIA provides those functions. Driving an LCD directly would hog the CPU and complicate timing.
