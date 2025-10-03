!to "software/build/hello_world.bin", plain
!cpu 65c02

* = $8000

!addr PORTB   = $6000
!addr PORTA   = $6001
!addr DDRB    = $6002
!addr DDRA    = $6003

ENABLE = %10000000
RW = %01000000
RS = %00100000

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

print_char:
    jsr lcd_wait

    sta PORTB
    lda #RS
    sta PORTA
    lda #(RS | ENABLE)
    sta PORTA
    lda #RS
    sta PORTA
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
    lda #0
    sta PORTA
    lda #ENABLE
    sta PORTA
    lda #0
    sta PORTA
    rts

lcd_wait:
    pha
    lda #%00000000
    sta DDRB

lcd_busy:
    lda #RW
    sta PORTA
    lda #(RW | ENABLE)
    sta PORTA

    lda PORTB
    and #%10000000
    bne lcd_busy

    lda #RW
    sta PORTA

    lda #%11111111
    sta DDRB
    pla
    rts
nmi: rti
irq: rti

* = $FFFA
!word nmi, reset, irq