!to "software/build/count.bin", plain

* = $8000           ; Set PC to beginning of EEPROM

!addr PORTA = $6001
!addr DDRA = $6003

reset:
    lda #$FF
    sta DDRA        ; Set data direction of Port A to output

    lda #$00        ; Load A with 0

loop:
    sta PORTA       ; Store A on the VIA

                    ; Wait 256 * 256 operations
    ldx #$FF        ; Outer Count
-   ldy #$FF        ; Inner count
--  dey             ; Decrement inner
    bne --          ; if not 0, keep decrementing
    dex             ; decrement x
    bne -           ; if x not zero, reset y and go again

    clc             ; clear carry bit
    adc #$01        ; increment A

    jmp loop        ; loop

nmi: rti
irq: rti

* = $FFFA           ; Set vectors at end of EEPROM
!word nmi, reset, irq