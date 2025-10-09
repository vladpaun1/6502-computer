!to "software/build/6btn_text_editor.bin", plain
!cpu 65c02

; =============================================================================
; 6btn_text_editor — VIA+HD44780 editor with modes & insert dial
; =============================================================================
* = $8000

; -----------------------------------------------------------------------------
; VIA addresses
; -----------------------------------------------------------------------------
!addr PORTB   = $6000
!addr PORTA   = $6001
!addr DDRB    = $6002
!addr DDRA    = $6003
!addr PCR     = $600c
!addr IFR     = $600d
!addr IER     = $600e

; -----------------------------------------------------------------------------
; Port A mapping: PA7=RW, PA6=RS, PA5..PA0 = buttons
; -----------------------------------------------------------------------------
RW = %10000000                  ; PA7
RS = %01000000                  ; PA6

; PCR/CB2 control (only bits 7..5 affect CB2). RMW to preserve other bits.
CB2_HIGH_BITS = %11100000       ; CB2 = High output
CB2_LOW_BITS  = %11000000       ; CB2 = Low output
PRESERVE_MASK = %00011111       ; keep bits 4..0

SHIFT_DISP_LEFT  = %00011000   ; shift display left, cursor follows visually
SHIFT_DISP_RIGHT = %00011100   ; shift display right
CURSOR_LEFT      = %00010000   ; what you already use
CURSOR_RIGHT     = %00010100


; -----------------------------------------------------------------------------
; Zero-page working pointers/temps
; -----------------------------------------------------------------------------
text_ptr          = $00         ; 16-bit pointer for message printing
jmp_ptr           = $02         ; 16-bit pointer for indirect JMP
tmp               = $04
tmp_ddrb          = $05
reset_insert_type = $06         ; flag: 1 when entering INSERT mode

; -----------------------------------------------------------------------------
; RAM state
; -----------------------------------------------------------------------------
MODE_ADDRESS            = $0200  ; current mode (0..NUM_MODES-1)
INSERT_TYPE_ADDRESS     = $0201  ; current insert type (0..NUM_INSERT_TYPES-1)
LAST_CURSOR_POS         = $0202  ; last DDRAM addr read (7-bit addr)
CURRENT_INSERT          = $0203  ; current glyph to insert/edit
CURRENT_SPECIAL_INDEX   = $0204  ; index into special_table

WIN_OFF = $0205          ; 0..24 (because 40-16 = 24)


; -----------------------------------------------------------------------------
; Modes
; -----------------------------------------------------------------------------
NUM_MODES   = 2
MODE_CURSOR = 0
MODE_INSERT = 1

mode_texts:
    !word mode1_text, mode3_text
mode1_text:   !text "<cursor mode>",0
mode3_text:   !text "i:",0

; -----------------------------------------------------------------------------
; Insert types
; -----------------------------------------------------------------------------
NUM_INSERT_TYPES     = 4
INSERT_TYPE_CHAR     = 0
INSERT_TYPE_UPPER    = 1
INSERT_TYPE_NUM      = 2
INSERT_TYPE_SPECIAL  = 3

insert_type_default_texts:
    !word insert_type1_default, insert_type2_default, insert_type3_default, insert_type4_default
insert_type1_default:    !text "<char_lo>:",0
insert_type2_default:    !text "<char_up>:",0
insert_type3_default:    !text "<num>:",0
insert_type4_default:    !text "<special>:",0

; Special glyph set (wraps)
SPECIAL_COUNT = 25
special_table:
    !byte ' ','.',',','-','_','?','!',';',':','+','/','\\','*','(',')','[',']','{','}','<','>','=','@','#','&'

; -----------------------------------------------------------------------------
; UI strings
; -----------------------------------------------------------------------------
msg:    !text "Hello, world!",0


; =============================================================================
; Reset / Init
; =============================================================================
reset:
    ldx #$FF
    txs

    jsr initialize_lcd
    jsr init_irq_for_ca1
    cli                         ; enable IRQs

    ; Greeting on power-up
    lda #<msg
    sta text_ptr
    lda #>msg
    sta text_ptr + 1
    jsr print_msg

    jsr lcd_get_addr    ; save cursor
    sta LAST_CURSOR_POS
    stz WIN_OFF



    ; Initial editor state
    lda #MODE_CURSOR
    sta MODE_ADDRESS

    lda #INSERT_TYPE_CHAR
    sta INSERT_TYPE_ADDRESS

    lda #'a'
    sta CURRENT_INSERT

    jsr show_current_mode_on_line2

loop:
    jmp loop

; =============================================================================
; IRQ (CA1 on falling edge, buttons on PA5..PA0 active-low)
; =============================================================================
irq:
    pha
    phx
    phy

    lda IFR
    and #%00000010
    beq irq_done                 ; not a CA1 IRQ

    ; Latch cursor and clear CA1 flag by reading IRA
    jsr lcd_get_addr
    sta LAST_CURSOR_POS

    lda PORTA
    and #%00111111               ; keep PA5..PA0

    bit #%00000001               ; PA0 = mode toggle
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

irq_mode:   jsr toggle_modes     : jmp irq_done
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

; =============================================================================
; Cursor helpers
; =============================================================================
reset_cursor:
    lda LAST_CURSOR_POS
    ora #%10000000               ; Set DDRAM addr command
    jsr lcd_instruction
    rts

; =============================================================================
; LEFT handlers
; =============================================================================
left_handlers:
    !word left_m0, left_m1

dispatch_left:
    jsr mode_x2
    lda left_handlers, x
    sta jmp_ptr
    lda left_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

left_m0:
    jsr lcd_get_addr            ; A = AC
    beq @wrap_to_end            ; absolute start → wrap to end (see below)

    ; at left edge? (AC == WIN_OFF)
    cmp WIN_OFF
    bne @just_cursor_left

    ; left edge while scrolled? unscroll one step as we move left
    lda WIN_OFF
    beq @just_cursor_left       ; already at leftmost window

    lda #CURSOR_LEFT                    ; CURSOR_LEFT
    jsr lcd_instruction
    lda #SHIFT_DISP_RIGHT                    ; SHIFT_DISP_RIGHT
    jsr lcd_instruction
    dec WIN_OFF
    jmp irq_done

@just_cursor_left:
    lda #CURSOR_LEFT                    ; CURSOR_LEFT
    jsr lcd_instruction
    jmp irq_done

@wrap_to_end:
    ; optional: wrap to logical end of the 40-char line and show its last window
    ; AC := $27, WIN_OFF := 24, shift display left 24 times
    lda #$27
    ora #%10000000
    jsr lcd_instruction

    ; scroll left until WIN_OFF == 24
@scroll_left_to_last:
    lda WIN_OFF
    cmp #24
    beq @done
    lda #SHIFT_DISP_LEFT                    ; SHIFT_DISP_LEFT
    jsr lcd_instruction
    inc WIN_OFF
    jmp @scroll_left_to_last
@done:
    jmp irq_done


left_m1:                         ; insert: prev type
    jsr dec_insert_type
    jsr reset_cursor
    jmp irq_done

; =============================================================================
; RIGHT handlers
; =============================================================================
right_handlers:
    !word right_m0, right_m1

dispatch_right:
    jsr mode_x2
    lda right_handlers, x
    sta jmp_ptr
    lda right_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

; A = AC (0x00..0x27)
right_m0:
    jsr lcd_get_addr
    cmp #$27
    beq @wrap_to_start          ; at absolute end → wrap & unscroll

    ; at right edge? (AC == WIN_OFF + 15)
    sta tmp                     ; tmp = AC
    lda WIN_OFF
    clc
    adc #15
    cmp tmp
    bne @just_cursor_right

    ; we're at right edge of the window
    lda WIN_OFF
    cmp #24
    bcs @just_cursor_right      ; already fully scrolled → just move cursor

    lda #CURSOR_RIGHT                   ; CURSOR_RIGHT
    jsr lcd_instruction
    lda #SHIFT_DISP_LEFT           ; SHIFT_DISP_LEFT
    jsr lcd_instruction
    inc WIN_OFF
    jmp irq_done

@just_cursor_right:
    lda #$14                    ; CURSOR_RIGHT
    jsr lcd_instruction
    jmp irq_done

@wrap_to_start:
    ; go to $00 and unscroll WIN_OFF steps
    lda #%10000000
    jsr lcd_instruction
@unscroll:
    lda WIN_OFF
    beq @done
    lda #SHIFT_DISP_RIGHT                    ; SHIFT_DISP_RIGHT
    jsr lcd_instruction
    dec WIN_OFF
    bne @unscroll
@done:
    jmp irq_done


right_m1:                        ; insert: next type
    jsr inc_insert_type
    jsr reset_cursor
    jmp irq_done

; =============================================================================
; UP handlers
; =============================================================================
up_handlers:
    !word up_m0, up_m1

dispatch_up:
    jsr mode_x2
    lda up_handlers, x
    sta jmp_ptr
    lda up_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

up_m0:
    ; go to start of line
    jsr lcd_line1_home
    jmp irq_done

up_m1:                           ; insert: decrement glyph
    jsr dispatch_insert_dec
    jsr show_insert_type_on_line2
    jmp irq_done

; =============================================================================
; DOWN handlers
; =============================================================================
down_handlers:
    !word down_m0, down_m1

dispatch_down:
    jsr mode_x2
    lda down_handlers, x
    sta jmp_ptr
    lda down_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

down_m0:     
    ; go to end of line 1
    lda #%10001111
    jsr lcd_instruction
    jmp irq_done

down_m1:                         ; insert: increment glyph
    jsr dispatch_insert_inc
    jsr show_insert_type_on_line2
    jmp irq_done

; =============================================================================
; ENTER handlers
; =============================================================================
enter_handlers:
    !word enter_m0, enter_m1

dispatch_enter:
    jsr mode_x2
    lda enter_handlers, x
    sta jmp_ptr
    lda enter_handlers+1, x
    sta jmp_ptr+1
    jmp (jmp_ptr)

enter_m0:                        ; backspace shift
    jsr lcd_backspace_shift
    jmp irq_done

; enter_m1 — insert at cursor; scroll window if at right edge
enter_m1:
    ; 1) Check absolute end (AC == $27) BEFORE printing
    jsr lcd_get_addr
    cmp #$27
    bne @not_last

    ; --- At the very last cell: print and keep cursor there ---
    lda CURRENT_INSERT
    jsr print_char          ; AC would advance to next line; we don't want that
    lda #CURSOR_LEFT                ; CURSOR_LEFT
    jsr lcd_instruction     ; move back to $27 and stop
    jmp irq_done

@not_last:
    ; 2) Snapshot old AC to test right-edge; then print (which advances AC)
    sta tmp                 ; tmp := old AC
    lda CURRENT_INSERT
    jsr print_char

    ; 3) If we were at the right edge (old AC == WIN_OFF+15) and can still scroll,
    ;    shift window left once to keep the cursor visually at the edge.
    lda WIN_OFF
    clc
    adc #15
    cmp tmp
    bne @done               ; not at right edge → nothing else
    lda WIN_OFF
    cmp #24
    bcs @done               ; already fully scrolled → don't shift

    lda #SHIFT_DISP_LEFT                ; SHIFT_DISP_LEFT
    jsr lcd_instruction
    inc WIN_OFF

@done:
    jmp irq_done


; =============================================================================
; Insert type change
; =============================================================================
inc_insert_type:
    inc INSERT_TYPE_ADDRESS
    lda INSERT_TYPE_ADDRESS
    cmp #NUM_INSERT_TYPES
    bcc +
    stz INSERT_TYPE_ADDRESS
+   
    jsr set_default_insert_for_type
    jsr show_insert_type_on_line2
    rts

dec_insert_type:
    dec INSERT_TYPE_ADDRESS
    lda INSERT_TYPE_ADDRESS
    cmp #$FF
    bne +
    lda #NUM_INSERT_TYPES - 1
    sta INSERT_TYPE_ADDRESS
+   
    jsr set_default_insert_for_type
    jsr show_insert_type_on_line2
    rts

; =============================================================================
; Mode toggle
; =============================================================================
toggle_modes:
    inc MODE_ADDRESS
    lda MODE_ADDRESS
    cmp #NUM_MODES
    bcc +
    stz MODE_ADDRESS
+   jsr show_current_mode_on_line2
    rts

; =============================================================================
; UI line helpers
; =============================================================================
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
append_on_line_2:
    jsr print_msg
    rts

; =============================================================================
; Mode/Insert label rendering
; =============================================================================
; X = mode * 2
mode_x2:
    ldx MODE_ADDRESS
    txa
    asl
    tax
    rts

; X = insert_type * 2
insert_type_x2:
    ldx INSERT_TYPE_ADDRESS
    txa
    asl
    tax
    rts

show_insert_type_on_line2:
    stz reset_insert_type
    jmp show_mode_and_maybe_insert

show_current_mode_on_line2:
    lda #1
    sta reset_insert_type
show_mode_and_maybe_insert:
    jsr mode_x2
    lda mode_texts, x
    sta text_ptr
    lda mode_texts+1, X
    sta text_ptr+1
    jsr print_on_line2

    lda MODE_ADDRESS
    cmp #MODE_INSERT
    bne @done

    ; entering INSERT? optionally reset type to 0 then set default glyph
    lda reset_insert_type
    beq @skip_reset
    stz INSERT_TYPE_ADDRESS
    jsr set_default_insert_for_type
@skip_reset:
    jsr append_insert_type_on_line2
    jsr append_current_insert_on_line2
@done:
    jsr reset_cursor
    rts

append_insert_type_on_line2:
    jsr insert_type_x2
    lda insert_type_default_texts, x
    sta text_ptr
    lda insert_type_default_texts+1, X
    sta text_ptr+1
    jsr append_on_line_2
    rts

; =============================================================================
; INSERT glyph seed & write
; =============================================================================
; Set CURRENT_INSERT (and special index) to first glyph for current type
set_default_insert_for_type:
    lda INSERT_TYPE_ADDRESS
    cmp #INSERT_TYPE_CHAR
    bne @chk_upper
    lda #'a'
    sta CURRENT_INSERT
    rts
@chk_upper:
    cmp #INSERT_TYPE_UPPER
    bne @chk_num
    lda #'A'
    sta CURRENT_INSERT
    rts
@chk_num:
    cmp #INSERT_TYPE_NUM
    bne @chk_special
    lda #'0'
    sta CURRENT_INSERT
    rts
@chk_special:
    stz CURRENT_SPECIAL_INDEX
    ldy CURRENT_SPECIAL_INDEX
    lda special_table,y
    sta CURRENT_INSERT
    rts


append_current_insert_on_line2:
    lda #'<'
    jsr print_char
    
    lda CURRENT_INSERT
    cmp #' '
    bne +
    lda #'s'
    jsr print_char
    lda #'p'

+   jsr print_char
    lda #'>'
    jsr print_char
    rts


; =============================================================================
; INSERT increment/decrement dispatchers
; =============================================================================
dispatch_insert_inc:
    jsr insert_type_x2
    lda insert_inc_handlers, X
    sta jmp_ptr
    lda insert_inc_handlers+1, X
    sta jmp_ptr+1
    jmp (jmp_ptr)

dispatch_insert_dec:
    jsr insert_type_x2
    lda insert_dec_handlers, X
    sta jmp_ptr
    lda insert_dec_handlers+1, X
    sta jmp_ptr+1
    jmp (jmp_ptr)

; Tables
insert_inc_handlers:
    !word insert_char_inc, insert_upper_inc, insert_num_inc, insert_special_inc
insert_dec_handlers:
    !word insert_char_dec, insert_upper_dec, insert_num_dec, insert_special_dec

; ---- CHAR: 'a'..'z' wrap ----
insert_char_inc:
    lda CURRENT_INSERT
    cmp #'a'
    bcc @set_a
    cmp #'z'
    beq @wrap_a
    bcs @set_a
    clc
    adc #1
    bne @store_char
@wrap_a:
    lda #'a'
@set_a:
@store_char:
    sta CURRENT_INSERT
    rts

insert_char_dec:
    lda CURRENT_INSERT
    cmp #'a'
    beq @wrap_z
    cmp #'z'
    bcc @ok_dec
    beq @ok_dec
    lda #'z'
    bne @store_dec
@ok_dec:
    sec
    sbc #1
    bcs @store_dec
@wrap_z:
    lda #'z'
@store_dec:
    sta CURRENT_INSERT
    rts

; ---- CHAR: 'A'..'Z' wrap ----
insert_upper_inc:
    lda CURRENT_INSERT
    cmp #'A'
    bcc @set_a
    cmp #'Z'
    beq @wrap_a
    bcs @set_a
    clc
    adc #1
    bne @store_char
@wrap_a:
    lda #'A'
@set_a:
@store_char:
    sta CURRENT_INSERT
    rts

insert_upper_dec:
    lda CURRENT_INSERT
    cmp #'A'
    beq @wrap_z
    cmp #'Z'
    bcc @ok_dec
    beq @ok_dec
    lda #'Z'
    bne @store_dec
@ok_dec:
    sec
    sbc #1
    bcs @store_dec
@wrap_z:
    lda #'Z'
@store_dec:
    sta CURRENT_INSERT
    rts



; ---- NUM: '0'..'9' wrap ----
insert_num_inc:
    lda CURRENT_INSERT
    cmp #'0'
    bcc @set_0
    cmp #'9'
    beq @wrap_0
    bcs @set_0
    clc
    adc #1
    bne @store_num
@wrap_0:
    lda #'0'
@set_0:
@store_num:
    sta CURRENT_INSERT
    rts

insert_num_dec:
    lda CURRENT_INSERT
    cmp #'0'
    beq @wrap_9
    cmp #'9'
    bcc @ok_dec
    beq @ok_dec
    lda #'9'
    bne @store_dec
@ok_dec:
    sec
    sbc #1
    bcs @store_dec
@wrap_9:
    lda #'9'
@store_dec:
    sta CURRENT_INSERT
    rts

; ---- SPECIAL: table wrap using CURRENT_SPECIAL_INDEX ----
insert_special_inc:
    lda CURRENT_SPECIAL_INDEX
    clc
    adc #1
    cmp #SPECIAL_COUNT
    bcc @idx_ok
    lda #0
@idx_ok:
    sta CURRENT_SPECIAL_INDEX
    tay
    lda special_table,y
    sta CURRENT_INSERT
    rts

insert_special_dec:
    lda CURRENT_SPECIAL_INDEX
    beq @wrap_last
    sec
    sbc #1
    bne @idx_set
@wrap_last:
    lda #SPECIAL_COUNT-1
@idx_set:
    sta CURRENT_SPECIAL_INDEX
    tay
    lda special_table,y
    sta CURRENT_INSERT
    rts

; =============================================================================
; LCD helpers (busy-flag polling, data/instruction writes)
; =============================================================================
print_msg:
    ldy #0
@loop:
    lda (text_ptr),y
    beq @done
    jsr print_char
    inc text_ptr
    bne @loop
    inc text_ptr+1
    jmp @loop
@done:
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

; RS=0, RW=0
lcd_instruction:
    jsr lcd_wait
    sta PORTB
    lda #$00
    sta PORTA
    jsr lcd_strobe
    rts

; VIA + LCD init
initialize_lcd:
    lda #%11111111
    sta DDRB                      ; PB outputs
    lda #%11000000
    sta DDRA                      ; PA7..PA6 outputs, PA5..PA0 inputs

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

; Read current DDRAM addr (7-bit), returns in A
lcd_get_addr:
    lda DDRB
    pha
    lda #%00000000
    sta DDRB

    lda #RW
    sta PORTA

    ; E HIGH
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR

    lda PORTB
    and #%01111111
    tax

    ; E LOW
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    pla
    sta DDRB
    txa
    rts

; Read data at current addr into A (no advance here)
lcd_read_data:
    jsr lcd_wait
    lda DDRB
    sta tmp_ddrb
    lda #$00
    sta DDRB

    lda #(RW | RS)                ; RS=1,RW=1
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

    lda tmp_ddrb
    sta DDRB

    pla
    rts

; Backspace with shift (line-local)
lcd_backspace_shift:
    jsr lcd_get_addr
    tax
    tay

    txa
    and #%01000000
    sta tmp                      ; line bit (0x40)

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

; =============================================================================
; VIA: CA1 IRQ setup
; =============================================================================
init_irq_for_ca1:
    ; CA1 falling edge (PCR bit0 = 0)
    lda PCR
    and #%11111110
    sta PCR

    ; Clear any pending CA1 by reading IRA
    lda PORTA

    ; Enable CA1 interrupt (IER: bit1), write 1s with bit7=1 to enable
    lda #%10000010
    sta IER
    rts

; =============================================================================
; Vectors
; =============================================================================
nmi: rti

* = $FFFA
!word nmi, reset, irq
