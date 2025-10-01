!to "software/build/count_16bit.bin", plain
!cpu 65c02

* = $8000                 ; ROM entry point

; ---------------------------------------------------------------------------
; W65C22 VIA base map at $6000
;   $6000  ORB  (Port B data)
;   $6001  ORA  (Port A data)
;   $6002  DDRB (Port B data direction)
;   $6003  DDRA (Port A data direction)
;   $600F  ORA (no-handshake mirror, write-only)  ; safer write to Port A
; ---------------------------------------------------------------------------
!addr PORTB   = $6000
!addr PORTA   = $6001
!addr DDRB    = $6002
!addr DDRA    = $6003
!addr ORA_NH  = $600F

; Zero-page scratch for delay (doesn't disturb X/Y)
!addr D0 = $00
!addr D1 = $01

; ---------------------------------------------------------------------------
; Reset
; ---------------------------------------------------------------------------
reset:
    sei                     ; Mask IRQs during bring-up
    cld                     ; Ensure binary (not BCD) arithmetic

    lda #$FF                ; All pins as outputs
    sta DDRA
    sta DDRB

    ldx #$00                ; X = high byte
    ldy #$00                ; Y = low  byte

; ---------------------------------------------------------------------------
; Main loop: present high first, then low, then delay, then increment
; ---------------------------------------------------------------------------
loop:
    stx PORTA               ; High byte first
    stx ORA_NH              ; Also hit the no-handshake mirror for PA
    sty PORTB               ; Then low byte

    jsr wait                ; Visible rate

    iny                     ; ++low
    bne loop
    inx                     ; carry to high
    jmp loop

; ---------------------------------------------------------------------------
; Delay that does NOT touch X or Y.
; Uses A and two ZP counters (D0/D1). Safe on 65C02 and with VIA.
; ---------------------------------------------------------------------------
wait:
    lda #$20                ; Outer loop count (tune as needed)
    sta D1
-   lda #$FF
    sta D0
--  dec D0
    bne --
    dec D1
    bne -
    rts

; ---------------------------------------------------------------------------
; Interrupt handlers
; ---------------------------------------------------------------------------
nmi: rti
irq: rti

; ---------------------------------------------------------------------------
; Vectors
; ---------------------------------------------------------------------------
* = $FFFA
!word nmi, reset, irq
