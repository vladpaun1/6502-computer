!to "software/build/6btn_text_editor.bin", plain
!cpu 65c02

* = $8000

!addr PORTB   = $6000
!addr PORTA   = $6001
!addr DDRB    = $6002
!addr DDRA    = $6003
!addr PCR     = $600c
!addr IFR     = $600d
!addr IER     = $600e

; Port A mapping:
;   PA7 = RW, PA6 = RS, PA5..PA0 = inputs (buttons)
RW = %10000000                  ; PA7
RS = %01000000                  ; PA6

; PCR control (only bits 7..5 affect CB2). We'll RMW to preserve other bits.
CB2_HIGH_BITS = %11100000       ; CB2 = High output
CB2_LOW_BITS  = %11000000       ; CB2 = Low output
PRESERVE_MASK = %00011111       ; keep bits 4..0

text_ptr = $00

; ---- modes ----
MODE_ADDRESS= $0200
NUM_MODES   = 3          ; change to any N

MODE_CURSOR = 0
MODE_TEXT   = 1
MODE_INSERT = 2

jmp_ptr     = $02        ; extra ZP pointer for indirect JMP

mode_texts:
    !word mode1_text, mode2_text, mode3_text


mode1_text:   !text "cursor mode",0
mode2_text:   !text "text mode",0
mode3_text:   !text "insert mode",0



msg:    !text "Hello, world!",0
left:   !text "left",0
up:     !text "up",0
down:   !text "down",0
right:   !text "right",0
enter:  !text "enter",0

reset:
    ldx #$FF
    txs

    jsr initialize_lcd
    jsr init_irq_for_ca1        ; enable CA1 IRQ (falling edge)
    cli                         ; allow maskable interrupts
    
    lda #<msg
    sta text_ptr
    lda #>msg
    sta text_ptr + 1
    jsr print_msg

    lda #MODE_CURSOR
    sta MODE_ADDRESS

    jsr show_current_mode_on_line2


loop:
    jmp loop



print_msg:
    ldy #0
print_loop:
    lda (text_ptr),y
    beq +
    jsr print_char
    inc text_ptr
    bne print_loop
    inc text_ptr+1
    jmp print_loop
+   rts
; ---------------- LCD HELPERS (E on CB2 via PCR), busy-flag polling ----------------

; Pulse E on CB2: HIGH then LOW (RMW to preserve CA1/CA2/CB1 bits)
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

; Write data byte in A (RS=1, RW=0)
print_char:
    jsr lcd_wait          ; wait until not busy

    pha

    sta PORTB             ; put data on D0..D7
    lda #RS               ; RS=1, RW=0
    sta PORTA
    jsr lcd_strobe        ; E pulse on CB2
    pla
    rts

; Write instruction byte in A (RS=0, RW=0)
lcd_instruction:
    jsr lcd_wait
    sta PORTB
    lda #$00              ; RS=0, RW=0
    sta PORTA
    jsr lcd_strobe
    rts

; VIA + LCD init
initialize_lcd:
    lda #%11111111
    sta DDRB              ; PB = outputs (LCD data)
    lda #%11000000
    sta DDRA              ; PA7..PA6 outputs (RW,RS), PA5..PA0 inputs

    ; Force E (CB2) low idle
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    ; Function set: 8-bit, 2 lines, 5x8
    lda #%00111000
    jsr lcd_instruction
    ; Display ON, cursor ON, blink OFF
    lda #%00001110
    jsr lcd_instruction
    ; Entry mode: increment, no shift
    lda #%00000110
    jsr lcd_instruction
    ; Clear display
    lda #%00000001
    jsr lcd_instruction
    rts

; Busy-flag poll (no fixed delays). Reads DB7 while E is HIGH.
lcd_wait:
    pha
    lda #%00000000
    sta DDRB              ; PB = inputs for read

@busy:
    lda #RW               ; RS=0, RW=1  (since only RW bit set)
    sta PORTA

    ; E = HIGH
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR

    lda PORTB             ; read DB7..DB0 while E high
    pha                   ; save read in stack

    ; E = LOW
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    pla
    and #%10000000        ; test busy flag (DB7)
    bne @busy             ; if busy, loop

    lda #%11111111
    sta DDRB              ; PB back to outputs
    pla
    rts

init_irq_for_ca1:
    ; Set CA1 to trigger on falling edge (PCR bit0 = 0)
    lda PCR
    and #%11111110
    sta PCR

    ; Clear any pending CA1 by reading IRA
    lda PORTA

    ; Enable CA1 interrupt (IER: bit1, with bit7=1 to enable)
    lda #%10000010
    sta IER
    rts

irq:
    pha
    phx
    phy

    lda IFR
    and #%00000010
    beq irq_done

    lda PORTA
    and #%00111111

    bit #%00000001      ; PA0 = mode toggle
    beq irq_mode
    bit #%00000010
    beq irq_left
    bit #%00000100
    beq irq_up
    bit #%00001000
    beq irq_down
    bit #%00010000
    beq irq_right
    bit #%00100000
    beq irq_enter
    jmp irq_done

irq_mode:
    jsr toggle_modes
    jmp irq_done

; --- dispatches (jump through handler tables based on mode) ---
irq_left:   jmp dispatch_left
irq_up:     jmp dispatch_up
irq_down:   jmp dispatch_down
irq_right:  jmp dispatch_right
irq_enter:  jmp dispatch_enter

irq_done:
    ply
    plx
    pla
    rti




; --------- LEFT handlers ----------
left_handlers:
    !word left_m0, left_m1, left_m2

dispatch_left:
    jsr mode_x2
    lda left_handlers, x
    sta jmp_ptr
    lda left_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

; Mode 0 (cursor mode): move cursor left (HD44780: 0001 0000)
left_m0:
    lda #%00010000
    jsr lcd_instruction
    jmp irq_done

; Mode 1 (text mode): just say "left" on line 2
left_m1:
    lda #<left
    sta text_ptr
    lda #>left
    sta text_ptr+1
    jsr print_on_line1
    jmp irq_done

left_m2:
    jmp irq_done


; --------- RIGHT handlers ----------
right_handlers:
    !word right_m0, right_m1, right_m2

dispatch_right:
    jsr mode_x2
    lda right_handlers, x
    sta jmp_ptr
    lda right_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

right_m0:                   ; cursor mode: cursor right (0001 0100)
    lda #%00010100
    jsr lcd_instruction
    jmp irq_done

right_m1:                   ; text mode: say "right"
    lda #<right
    sta text_ptr
    lda #>right
    sta text_ptr+1
    jsr print_on_line1
    jmp irq_done

right_m2:
    jmp irq_done


; --------- UP handlers ----------
up_handlers:
    !word up_m0, up_m1, up_m2

dispatch_up:
    jsr mode_x2
    lda up_handlers, x
    sta jmp_ptr
    lda up_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

up_m0:                              ; cursor mode: go to line 1, same column 
    jsr lcd_get_addr
    and #%00001111
    ora #%10000000                  ; Set DDRAM to line 1, col 0
    jsr lcd_instruction
    jmp irq_done

up_m1:
    lda #<up
    sta text_ptr
    lda #>up
    sta text_ptr+1
    jsr print_on_line1
    jmp irq_done

up_m2:
    jmp irq_done


; --------- DOWN handlers ----------
down_handlers:
    !word down_m0, down_m1, down_m2

dispatch_down:
    jsr mode_x2
    lda down_handlers, x
    sta jmp_ptr
    lda down_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

down_m0:                    ; cursor mode: line 2, same col
    jsr lcd_get_addr
    and #%00001111
    ora #%11000000
    jsr lcd_instruction
    jmp irq_done

down_m1:
    lda #<down
    sta text_ptr
    lda #>down
    sta text_ptr+1
    jsr print_on_line1
    jmp irq_done

down_m2:
    jmp irq_done

; --------- ENTER handlers ----------
enter_handlers:
    !word enter_m0, enter_m1, enter_m2

dispatch_enter:
    jsr mode_x2
    lda enter_handlers, x
    sta jmp_ptr
    lda enter_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

enter_m0:                   ; cursor mode: backspace
    jsr lcd_backspace_shift

    jmp irq_done

enter_m1:                   ; text mode: say "enter"
    lda #<enter
    sta text_ptr
    lda #>enter
    sta text_ptr+1
    jsr print_on_line1
    jmp irq_done

enter_m2:
    jmp irq_done



toggle_modes:
    inc MODE_ADDRESS
    lda MODE_ADDRESS
    cmp #NUM_MODES
    bcc +
    stz MODE_ADDRESS
+   jsr show_current_mode_on_line2
    rts

lcd_line1_home:
    lda #%10000000
    jsr lcd_instruction
    rts

lcd_clear_line1:
    jsr lcd_line1_home
    ldy #16
    lda #' '
@cl1:
    jsr print_char
    dey
    bne @cl1
    jsr lcd_line1_home
    rts

print_on_line1:
    jsr lcd_clear_line1
    jsr print_msg
    rts

lcd_line2_home:
    lda #%11000000
    jsr lcd_instruction
    rts

lcd_clear_line2:
    jsr lcd_line2_home
    ldy #16
    lda #' '
@cl2:
    jsr print_char
    dey
    bne @cl2
    jsr lcd_line2_home
    rts

print_on_line2:
    jsr lcd_clear_line2
    jsr print_msg
    rts

lcd_get_addr:
    lda DDRB
    pha

    lda #%00000000
    sta DDRB

    lda #RW
    sta PORTA

    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR

    lda PORTB
    and #%01111111
    tax

    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    pla
    sta DDRB
    txa
    rts

tmp_ddrb = $05
lcd_read_data:
    jsr lcd_wait
    lda DDRB
    sta tmp_ddrb

    lda #$00
    sta DDRB

    lda #(RW | RS)
    sta PORTA

    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR

    lda PORTB
    pha

    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    lda tmp_ddrb
    sta DDRB

    pla
    rts

tmp = $04
lcd_backspace_shift:
    jsr lcd_get_addr
    tax
    tay

    txa
    and #%01000000
    sta tmp

    tya
    and #%00001111
    tay
    beq finish_backspace
    dey
    tya
    tax
copy_loop:
    cpx #15
    bcs fill_last

    txa
    clc
    adc #1
    and #%00001111
    ora tmp
    ora #%10000000
    jsr lcd_instruction

    jsr lcd_read_data
    pha

    txa
    and #%00001111
    ora tmp
    ora #%10000000
    jsr lcd_instruction

    pla
    jsr print_char

    inx
    bra copy_loop

fill_last:
    lda #15
    and #%00001111
    ora tmp
    ora #%10000000
    jsr lcd_instruction

    lda #' '
    jsr print_char

    tya
    and #%00001111
    ora tmp
    ora #%10000000
    jsr lcd_instruction

finish_backspace:
    rts


; X = mode * 2
mode_x2:
    ldx MODE_ADDRESS
    txa
    asl
    tax
    rts
show_current_mode_on_line2:
    jsr mode_x2
    lda mode_texts, x
    sta text_ptr
    lda mode_texts+1, X
    sta text_ptr+1
    jsr print_on_line2
    rts

; ---------------- VECTORS ----------------
nmi: rti

* = $FFFA
!word nmi, reset, irq
