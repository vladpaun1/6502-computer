# 6502-computer
A personal project building a 65c02 based 8-bit breadboard computer and coding a lightweight custom OS for it

## Shopping list
### Mouser Order  
Items:
- W65C02S6TPG-14 — 8-bit Microprocessor — €11,11
- W65C22S6TPG-14 — I/O Controller Interface IC — €11,30  
- AS6C62256-55PCN — SRAM 32Kx8 55ns — €4,44  
- AT28C256-15PU — EEPROM 32Kx8 150ns — €9,99  
- ECS-100AX-010 — Oscillator 1MHz DIP-14 — €2,30  
- ECS-100AX-143 — Oscillator 14.31818MHz DIP-14 — €2,12  
- SN74HC138N — 3-to-8 Decoder — €1,08  
- SN74HC14N — Hex Schmitt-Trigger Inverter — €0,91  
- SN74HC245N — Octal Bus Transceiver — €0,71  
- SN74HC00N (x3) — Quad 2-Input NAND Gate — €1,83  
- SN74HC595N (x2) — 8-bit Shift Register — €2,88  
- SN74HC157N — Quad Data Selector/Multiplexer — €2,10  
- MCP130-485HI/TO — Supervisory Circuit — €0,46  
- BB830T (x2) — 830-Tie Point Transparent Breadboard — €18,10  
- LCD 16x2 RGB — Display Module — €11,01  
- K104K20X7RH5UH5 (x10) — 0.1µF MLCC Leaded Capacitors — €1,78  
- 68024-116HLF — 1x16 Pin Header — €0,83  

### Amazon Order  
Items:  
- 840-Piece Breadboard Jumper Wire Set (14 lengths, with clips)  
- TL866II Plus Universal Programmer (with 10 adapters)  
- AC to DC 9V 2A Power Supply (EU plug, center positive)  
- ELEGOO Electronic Fun Kit (breadboard, resistors, capacitors, LEDs, pots, etc.)  

## Dependencies

To build and flash ROMs for this project you’ll need:

- **Python 3.12+**  
  Used for helper scripts in the `tools/` directory.

- **[minipro-git](https://aur.archlinux.org/packages/minipro-git)**  
  Utility for programming EEPROMs/Flash devices with the TL866xx programmer.  
  On Arch-based systems you can install it from the AUR:  
  ```bash
  yay -S minipro-git
  ```
- **[ACME Cross Assembler](https://sourceforge.net/projects/acme-crossass/)**  
  A 6502/65C02 assembler used to build flat binary ROM images.  
  On Arch Linux it’s available in the official repos:
  ```bash
  sudo pacman -S acme
  ```
  Example usage:
  ```bash
  acme -f plain -o software/build/rom.bin software/src/main.asm
  ```
