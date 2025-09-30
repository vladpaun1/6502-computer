# ACME Assembler Notes

This project uses the **[ACME Cross Assembler](https://github.com/meonwax/acme-crossass)** to assemble 6502/65C02 programs into flat binary ROM images.  
On Arch Linux it’s packaged as `acme`:

```
sudo pacman -S acme
```

## Upstream Documentation

The full ACME docs are installed with the package (on Arch they live under `/usr/share/doc/acme/`).  
Useful files include:

- `QuickRef.txt` – cheatsheet of directives and syntax  
- `Help.txt` – main manual  
- `Example.txt` – sample assembly programs  
- `AddrModes.txt` – addressing modes reference  

If you don’t have these locally, you can also view them online here:

- [QuickRef.txt](https://github.com/martinpiper/ACME/blob/master/docs/QuickRef.txt)  
- [Help.txt](https://github.com/martinpiper/ACME/blob/master/docs/Help.txt)  

## Cheatsheet (common usage)

- **Comments**: `;` starts a comment  
- **Labels**:  
  ```
  start:      lda #$42
              sta $0000
  ```
- **Constants**: `$xx` hex, `%xxxx` binary, `123` decimal  
- **Directives**:  
  - `!to "file.bin", plain` → output as flat binary  
  - `* = $8000` → set program counter (origin)  
  - `!byte $01, $02, $03` → define raw bytes  
  - `!word $1234, $ABCD` → define 16-bit words (little endian)  
- **Vectors** (for 65C02 reset/IRQ/NMI):  
  ```
  * = $FFFA
  !word nmi, reset, irq
  ```
- **Including other files**:  
  ```
  !src "other.asm"
  ```

## Example Program

```
!to "software/build/rom.bin", plain   ; output binary
* = $8000                             ; load address

reset:
    lda #$42
    sta $0000
    rts

nmi:  rti
irq:  rti

* = $FFFA                             ; interrupt vectors
!word nmi, reset, irq
```

Assemble with:

```
acme -f plain -o software/build/rom.bin software/src/main.asm
```
