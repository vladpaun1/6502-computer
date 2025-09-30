!to "software/build/oscilate.bin", plain

* = $8000           ; Set PC to beginning of EEPROM

!addr PORTA = $6001
!addr DDRA = $6003

reset:
    lda #$FF
    sta DDRA        ; Set data direction of Port A to output

loop:
    lda #$55        ; Load A with 55
    sta PORTA       ; Store A on the VIA

    jsr wait_loop

    lda #$AA        ; Load A with aa
    sta PORTA       ; Store A on the VIA

    jsr wait_loop

    jmp loop        ; loop


wait_loop:          ; Wait 256 * 256 operations
    ldx #$FF        ; Outer Count
-   ldy #$FF        ; Inner count
--  dey             ; Decrement inner
    bne --          ; if not 0, keep decrementing
    dex             ; decrement x
    bne -           ; if x not zero, reset y and go again
    rts


nmi: rti
irq: rti

* = $FFFA           ; Set vectors at end of EEPROM
!word nmi, reset, irq