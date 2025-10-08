!to "software/build/hello_world.bin", plain
!cpu 65c02

* = $8000

!addr PORTB   = $6000
!addr PORTA   = $6001
!addr DDRB    = $6002
!addr DDRA    = $6003
!addr PCR     = $600c

RW = %10000000                  ; PA7
RS = %01000000                  ; PA6

; PCR/CB2 control (only bits 7..5 affect CB2). RMW to preserve other bits.
CB2_HIGH_BITS = %11100000       ; CB2 = High output
CB2_LOW_BITS  = %11000000       ; CB2 = Low output
PRESERVE_MASK = %00011111       ; keep bits 4..0



msg:    !text "Hello, world!",0

reset:
    ldx #$FF
    txs

    jsr initialize_lcd

    ldx #0
print_loop:
    lda msg, x
    beq loop
    jsr print_char
    inx
    jmp print_loop

loop:
    jmp loop

; RS=1, RW=0
print_char:
    jsr lcd_wait
    pha
    sta PORTB
    lda #RS
    sta PORTA
    jsr lcd_strobe
    pla
    rts

initialize_lcd:
    lda #%11111111
    sta DDRB
    lda #%11100000
    sta DDRA

    lda #%00111000
    jsr lcd_instruction
    lda #%00001110
    jsr lcd_instruction
    lda #%00000110
    jsr lcd_instruction
    lda #%00000001
    jsr lcd_instruction 

    rts

lcd_instruction:
    jsr lcd_wait
    sta PORTB
    lda #$00
    sta PORTA
    jsr lcd_strobe
    rts

; Pulse E on CB2: HIGH then LOW (RMW preserve)
lcd_strobe:
    pha
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR
    pla
    rts


; Busy-flag poll (read DB7 while E is HIGH)
lcd_wait:
    pha
    lda #%00000000
    sta DDRB                      ; PB inputs
@busy:
    lda #RW                       ; RS=0, RW=1
    sta PORTA
    ; E HIGH
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR
    lda PORTB
    pha
    ; E LOW
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR
    pla
    and #%10000000                ; DB7 busy?
    bne @busy
    lda #%11111111
    sta DDRB                      ; PB outputs
    pla
    rts
nmi: rti
irq: rti

* = $FFFA
!word nmi, reset, irq