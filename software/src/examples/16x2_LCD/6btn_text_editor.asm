!to "software/build/6btn_text_editor.bin", plain
!cpu 65c02

; =============================================================================
; 6btn_text_editor — W65C02 + VIA + HD44780 (16x2 visible / 40x2 DDRAM)
; Features: cursor mode / insert mode, 6-button CA1 IRQ dispatch,
;           horizontal windowing (WIN_OFF), backspace-shift, and line-2 status.
; Notes:
; - Zero Page is reserved for hot pointers and one scratch byte.
; - lcd_get_addr returns AC in A (clobbers X).
; - lcd_read_data returns data in A (clobbers Y).
; =============================================================================
* = $8000

; =============================================================================
; Hardware map (VIA + LCD bus)
; =============================================================================
!addr PORTB   = $6000
!addr PORTA   = $6001
!addr DDRB    = $6002
!addr DDRA    = $6003
!addr PCR     = $600c
!addr IFR     = $600d
!addr IER     = $600e

; ---- Port A mapping: PA7=RW, PA6=RS, PA5..PA0 = buttons (active-low) ----
RW = %10000000                  ; PA7
RS = %01000000                  ; PA6

; ---- VIA PCR/CB2: only bits 7..5 affect CB2; read-modify-write preserves others ----
CB2_HIGH_BITS = %11100000       ; CB2 = High output
CB2_LOW_BITS  = %11000000       ; CB2 = Low output
PRESERVE_MASK = %00011111       ; keep non-CB2 control bits 4..0

; =============================================================================
; Buttons (active-low on PA5..PA0)
; =============================================================================
BTN_MODE  = %00000001  ; PA0
BTN_LEFT  = %00000010  ; PA1
BTN_UP    = %00000100  ; PA2
BTN_DOWN  = %00001000  ; PA3
BTN_RIGHT = %00010000  ; PA4
BTN_ENTER = %00100000  ; PA5
BTN_MASK  = %00111111

; =============================================================================
; HD44780 geometry/opcodes (40x2 DDRAM, 16x2 visible window)
; =============================================================================
LCD_COLS        = 16
LCD_LINE_LEN    = 40
LCD_LAST_COL    = 39
LCD_MAX_WINOFF  = LCD_LINE_LEN - LCD_COLS         ; 24

AC_LINE0_BASE   = %00000000                        ; $00
AC_LINE1_BASE   = %01000000                        ; $40
AC_LINE0_LAST   = %00100111                        ; $27

CMD_SET_DDRAM   = %10000000

; Cursor / shift instructions
SHIFT_DISP_LEFT  = %00011000
SHIFT_DISP_RIGHT = %00011100
CURSOR_LEFT      = %00010000
CURSOR_RIGHT     = %00010100

; =============================================================================
; Zero Page (keep hot pointers + one temp only)
; =============================================================================
text_ptr          = $00         ; [ZP+0..1] 16-bit pointer for print_msg
jmp_ptr           = $02         ; [ZP+2..3] 16-bit indirect jump target
tmp               = $04         ; [ZP+4]    general temp (button latch etc.)
; $05.. reserved for future

; =============================================================================
; RAM state (main memory)
; =============================================================================
MODE_ADDRESS            = $0200  ; 0..NUM_MODES-1
INSERT_TYPE_ADDRESS     = $0201  ; 0..NUM_INSERT_TYPES-1
LAST_CURSOR_POS         = $0202  ; last DDRAM addr read (7-bit)
CURRENT_INSERT          = $0203  ; current glyph to insert/edit
CURRENT_SPECIAL_INDEX   = $0204  ; index into special_table
WIN_OFF                 = $0205  ; window offset 0..LCD_MAX_WINOFF (24)
RESET_INSERT_TYPE       = $0206  ; flag: 1 when entering INSERT mode
BS_TARGET_ADDR          = $0207  ; final DDRAM command after backspace

; =============================================================================
; Modes / Insert types and UI strings (ROM data)
; =============================================================================
NUM_MODES   = 2
MODE_CURSOR = 0
MODE_INSERT = 1

mode_texts:
    !word mode1_text, mode2_text
mode1_text: !text "<cursor mode>",0
mode2_text: !text "i:",0

NUM_INSERT_TYPES     = 4
INSERT_TYPE_CHAR     = 0
INSERT_TYPE_UPPER    = 1
INSERT_TYPE_NUM      = 2
INSERT_TYPE_SPECIAL  = 3

insert_type_default_texts:
    !word insert_type1_default, insert_type2_default, insert_type3_default, insert_type4_default
insert_type1_default: !text "<char_lo>:",0
insert_type2_default: !text "<char_up>:",0
insert_type3_default: !text "<num>:",0
insert_type4_default: !text "<special>:",0

; Special glyph set (wraps)
SPECIAL_COUNT = 25
special_table:
    !byte ' ','.',',','-','_','?','!',';',':','+','/','\\','*','(',')','[',']','{','}','<','>','=','@','#','&'

; Power-up banner
msg: !text "Hello, world!",0

; =============================================================================
; Reset / Init
; =============================================================================
reset:
    sei
    ldx #$FF
    txs

    jsr initialize_lcd
    jsr init_irq_for_ca1
    cli                         ; enable IRQs

    ; Greeting on power-up
    lda #<msg      : sta text_ptr
    lda #>msg      : sta text_ptr + 1
    jsr print_msg

    ; Capture current cursor and reset window
    jsr lcd_get_addr
    sta LAST_CURSOR_POS
    stz WIN_OFF

    ; Initial editor state
    lda #MODE_CURSOR        : sta MODE_ADDRESS
    lda #INSERT_TYPE_CHAR   : sta INSERT_TYPE_ADDRESS
    lda #'a'                : sta CURRENT_INSERT

    jsr show_current_mode_on_line2

main_loop:
    jmp main_loop

; =============================================================================
; IRQ (CA1 falling edge). Buttons on PA5..PA0 are active-low.
; BIT #mask + BEQ branches when bit is 0 (i.e., pressed).
; =============================================================================
irq:
    pha
    phx
    phy

    lda IFR
    and #%00000010
    beq irq_done                 ; not a CA1 IRQ

    ; Latch & clear CA1 early, keep only button bits
    lda PORTA
    and #BTN_MASK
    sta tmp                      ; save buttons (still active-low)

    ; Also sample DDRAM address once for helpers
    jsr lcd_get_addr
    sta LAST_CURSOR_POS

    ; Dispatch on buttons
    lda tmp
    bit #BTN_MODE   : beq irq_mode
    bit #BTN_LEFT   : beq irq_left
    bit #BTN_UP     : beq irq_up
    bit #BTN_DOWN   : beq irq_down
    bit #BTN_RIGHT  : beq irq_right
    bit #BTN_ENTER  : beq irq_enter
    ; else nothing pressed/handled

    jmp irq_done

irq_mode:   jsr toggle_modes        : jmp irq_done
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
; reset_cursor: restore cursor to LAST_CURSOR_POS.
reset_cursor:
    lda LAST_CURSOR_POS
    ora #CMD_SET_DDRAM
    jsr lcd_instruction
    rts

; =============================================================================
; LEFT handlers
; =============================================================================
left_handlers:
    !word left_m0, left_m1

dispatch_left:
    jsr mode_x2
    lda left_handlers, x    : sta jmp_ptr
    lda left_handlers+1, x  : sta jmp_ptr+1
    jmp (jmp_ptr)

; left_m0: cursor-mode ←
left_m0:
    jsr lcd_get_addr            ; A = AC
    beq @wrap_to_end            ; at absolute start → wrap to end

    ; at left edge? (AC == WIN_OFF)
    cmp WIN_OFF
    bne @just_left

    ; left edge while scrolled? unscroll one step as we move left
    lda WIN_OFF
    beq @just_left              ; already at leftmost window

    lda #CURSOR_LEFT
    jsr lcd_instruction

    dec WIN_OFF
    jsr shift_right_preserve_l2
    jmp irq_done

@just_left:
    lda #CURSOR_LEFT
    jsr lcd_instruction
    jmp irq_done

@wrap_to_end:
    jsr wrap_to_end_scroll
    jmp irq_done

; left_m1: insert-mode ←  (prev insert type)
left_m1:
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
    lda right_handlers, x    : sta jmp_ptr
    lda right_handlers+1, x  : sta jmp_ptr+1
    jmp (jmp_ptr)

; right_m0: cursor-mode →
right_m0:
    jsr lcd_get_addr
    cmp #AC_LINE0_LAST
    beq @wrap_to_start          ; at absolute end → wrap & unscroll

    ; at right edge? (AC == WIN_OFF + 15)
    sta tmp                     ; tmp = AC
    lda WIN_OFF
    clc
    adc #15
    cmp tmp
    bne @just_right

    ; we're at visible right edge and can still scroll
    lda WIN_OFF
    cmp #LCD_MAX_WINOFF
    bcs @just_right             ; fully scrolled → just move cursor

    lda #CURSOR_RIGHT
    jsr lcd_instruction

    inc WIN_OFF
    jsr shift_left_preserve_l2
    jmp irq_done

@just_right:
    lda #CURSOR_RIGHT
    jsr lcd_instruction
    jmp irq_done

@wrap_to_start:
    jsr wrap_to_start_unscroll
    jmp irq_done

; right_m1: insert-mode → (next insert type)
right_m1:
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
    lda up_handlers, x    : sta jmp_ptr
    lda up_handlers+1, x  : sta jmp_ptr+1
    jmp (jmp_ptr)

; up_m0: go to line start and unscroll
up_m0:
    jsr wrap_to_start_unscroll
    jmp irq_done

; up_m1: insert-mode — decrement glyph
up_m1:
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
    lda down_handlers, x    : sta jmp_ptr
    lda down_handlers+1, x  : sta jmp_ptr+1
    jmp (jmp_ptr)

; down_m0: go to logical line end and scroll window to last
down_m0:
    jsr wrap_to_end_scroll
    jmp irq_done

; down_m1: insert-mode — increment glyph
down_m1:
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
    lda enter_handlers, x    : sta jmp_ptr
    lda enter_handlers+1, x  : sta jmp_ptr+1
    jmp (jmp_ptr)

; enter_m0: backspace with shift
enter_m0:
    jsr lcd_backspace_shift
    jmp irq_done

; enter_m1: insert CURRENT_INSERT at cursor, with window follow on right edge
enter_m1:
    jsr lcd_get_addr
    cmp #AC_LINE0_LAST
    bne @not_last

    ; At very last cell: print and keep cursor there
    lda CURRENT_INSERT
    jsr print_char
    lda #CURSOR_LEFT
    jsr lcd_instruction
    jmp irq_done

@not_last:
    sta tmp                     ; tmp := old AC before print (auto-advances)
    lda CURRENT_INSERT
    jsr print_char

    ; If we were at right edge (old AC == WIN_OFF+15) and can still scroll, shift once
    lda WIN_OFF
    clc
    adc #15
    cmp tmp
    bne @done
    lda WIN_OFF
    cmp #LCD_MAX_WINOFF
    bcs @done

    inc WIN_OFF
    jsr shift_left_preserve_l2
@done:
    jmp irq_done

; =============================================================================
; WRAP helpers (RTS-returning)
; =============================================================================
; wrap_to_start_unscroll: AC := $00; WIN_OFF→0 (shift right until done)
wrap_to_start_unscroll:
    lda #CMD_SET_DDRAM | AC_LINE0_BASE
    jsr lcd_instruction
@unscroll:
    lda WIN_OFF
    beq @done
    dec WIN_OFF
    jsr shift_right_preserve_l2
    jmp @unscroll
@done:
    rts

; wrap_to_end_scroll: AC := $27; WIN_OFF→LCD_MAX_WINOFF (shift left until done)
wrap_to_end_scroll:
    lda #CMD_SET_DDRAM | AC_LINE0_LAST
    jsr lcd_instruction
@scroll:
    lda WIN_OFF
    cmp #LCD_MAX_WINOFF
    beq @done
    inc WIN_OFF
    jsr shift_left_preserve_l2
    jmp @scroll
@done:
    rts

; =============================================================================
; Insert type change + dispatchers
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

; ---- Insert dispatchers ----
dispatch_insert_inc:
    jsr insert_type_x2
    lda insert_inc_handlers, X   : sta jmp_ptr
    lda insert_inc_handlers+1, X : sta jmp_ptr+1
    jmp (jmp_ptr)

dispatch_insert_dec:
    jsr insert_type_x2
    lda insert_dec_handlers, X   : sta jmp_ptr
    lda insert_dec_handlers+1, X : sta jmp_ptr+1
    jmp (jmp_ptr)

; ---- Insert tables ----
insert_inc_handlers:
    !word insert_char_inc, insert_upper_inc, insert_num_inc, insert_special_inc
insert_dec_handlers:
    !word insert_char_dec, insert_upper_dec, insert_num_dec, insert_special_dec

; ---- Seed CURRENT_INSERT for type ----
set_default_insert_for_type:
    lda INSERT_TYPE_ADDRESS
    cmp #INSERT_TYPE_CHAR   : bne @chk_upper
    lda #'a'                : sta CURRENT_INSERT : rts
@chk_upper:
    cmp #INSERT_TYPE_UPPER  : bne @chk_num
    lda #'A'                : sta CURRENT_INSERT : rts
@chk_num:
    cmp #INSERT_TYPE_NUM    : bne @chk_special
    lda #'0'                : sta CURRENT_INSERT : rts
@chk_special:
    stz CURRENT_SPECIAL_INDEX
    ldy CURRENT_SPECIAL_INDEX
    lda special_table,y
    sta CURRENT_INSERT
    rts

; ---- CHAR: 'a'..'z' wrap ----
insert_char_inc:
    lda CURRENT_INSERT
    cmp #'a'        : bcc @set_a
    cmp #'z'        : beq @wrap_a
    bcs @set_a
    clc
    adc #1          : bne @store
@wrap_a: lda #'a'
@set_a:
@store:  sta CURRENT_INSERT
    rts

insert_char_dec:
    lda CURRENT_INSERT
    cmp #'a'        : beq @wrap_z
    cmp #'z'        : bcc @dec_ok
    beq @dec_ok
    lda #'z'        : bne @store
@dec_ok:
    sec
    sbc #1          : bcs @store
@wrap_z:
    lda #'z'
@store:
    sta CURRENT_INSERT
    rts

; ---- UPPER: 'A'..'Z' wrap ----
insert_upper_inc:
    lda CURRENT_INSERT
    cmp #'A'        : bcc @set_a
    cmp #'Z'        : beq @wrap_a
    bcs @set_a
    clc
    adc #1          : bne @store
@wrap_a: lda #'A'
@set_a:
@store:  sta CURRENT_INSERT
    rts

insert_upper_dec:
    lda CURRENT_INSERT
    cmp #'A'        : beq @wrap_z
    cmp #'Z'        : bcc @dec_ok
    beq @dec_ok
    lda #'Z'        : bne @store
@dec_ok:
    sec
    sbc #1          : bcs @store
@wrap_z:
    lda #'Z'
@store:
    sta CURRENT_INSERT
    rts

; ---- NUM: '0'..'9' wrap ----
insert_num_inc:
    lda CURRENT_INSERT
    cmp #'0'        : bcc @set_0
    cmp #'9'        : beq @wrap_0
    bcs @set_0
    clc
    adc #1          : bne @store
@wrap_0: lda #'0'
@set_0:
@store:  sta CURRENT_INSERT
    rts

insert_num_dec:
    lda CURRENT_INSERT
    cmp #'0'        : beq @wrap_9
    cmp #'9'        : bcc @dec_ok
    beq @dec_ok
    lda #'9'        : bne @store
@dec_ok:
    sec
    sbc #1          : bcs @store
@wrap_9:
    lda #'9'
@store:
    sta CURRENT_INSERT
    rts

; ---- SPECIAL: table wrap via CURRENT_SPECIAL_INDEX ----
insert_special_inc:
    lda CURRENT_SPECIAL_INDEX
    clc
    adc #1
    cmp #SPECIAL_COUNT : bcc @idx_ok
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
    sbc #1          : bne @set
@wrap_last:
    lda #SPECIAL_COUNT-1
@set:
    sta CURRENT_SPECIAL_INDEX
    tay
    lda special_table,y
    sta CURRENT_INSERT
    rts

; =============================================================================
; Mode helpers / UI rendering
; =============================================================================
; mode_x2:     X = mode * 2 (for word tables)
mode_x2:
    ldx MODE_ADDRESS
    txa
    asl
    tax
    rts

; insert_type_x2: X = insert_type * 2
insert_type_x2:
    ldx INSERT_TYPE_ADDRESS
    txa
    asl
    tax
    rts

; UI: show "mode" (line 2) and optionally insert type/current glyph
show_insert_type_on_line2:
    stz RESET_INSERT_TYPE
    jmp show_mode_and_maybe_insert

show_current_mode_on_line2:
    lda #1
    sta RESET_INSERT_TYPE
show_mode_and_maybe_insert:
    jsr lcd_clear_line2

    jsr mode_x2
    lda mode_texts, x
    sta text_ptr
    lda mode_texts+1, X
    sta text_ptr+1
    jsr print_on_line2

    lda MODE_ADDRESS
    cmp #MODE_INSERT
    bne @done

    ; entering INSERT? reset type and seed glyph if requested
    lda RESET_INSERT_TYPE
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

append_current_insert_on_line2:
    lda #'<'
    jsr print_char
    
    lda CURRENT_INSERT
    cmp #' '
    bne +
    lda #'s' : jsr print_char
    lda #'p'
+
    jsr print_char
    lda #'>'
    jsr print_char
    rts

; =============================================================================
; UI line helpers (position & clear)
; =============================================================================
lcd_line1_home:
    lda #CMD_SET_DDRAM | AC_LINE0_BASE
    jsr lcd_instruction
    rts

lcd_clear_line1:
    lda #CMD_SET_DDRAM | AC_LINE0_BASE
    jsr lcd_instruction
    ldy #LCD_LINE_LEN
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
    lda WIN_OFF
    ora #CMD_SET_DDRAM | AC_LINE1_BASE
    jsr lcd_instruction
    rts

lcd_clear_line2:
    lda #CMD_SET_DDRAM | AC_LINE1_BASE
    jsr lcd_instruction
    ldy #LCD_LINE_LEN
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
; LCD bus helpers (busy-flag polling, data/instruction writes)
; =============================================================================
; print_msg: print 0-terminated string at (text_ptr)
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

; lcd_strobe: pulse E on CB2 (HIGH then LOW), preserving other PCR bits
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

; print_char: RS=1, RW=0, data in A (A clobbered)
print_char:
    jsr lcd_wait
    pha
    sta PORTB
    lda #RS
    sta PORTA
    jsr lcd_strobe
    pla
    rts

; lcd_instruction: RS=0, RW=0, instruction in A (A clobbered)
lcd_instruction:
    jsr lcd_wait
    sta PORTB
    lda #$00
    sta PORTA
    jsr lcd_strobe
    rts

; initialize_lcd: set 8-bit, 2-line, 5x8; display on/cursor on; clear; idle E low
initialize_lcd:
    lda #%11111111         : sta DDRB      ; PB outputs
    lda #%11000000         : sta DDRA      ; PA7..PA6 outputs, PA5..PA0 inputs

    ; Force E (CB2) low idle
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    ; Function set: 8-bit, 2 lines, 5x8
    lda #%00111000         : jsr lcd_instruction
    ; Display ON, cursor ON, blink OFF
    lda #%00001110         : jsr lcd_instruction
    ; Entry mode: increment, no shift
    lda #%00000110         : jsr lcd_instruction
    ; Clear display
    lda #%00000001         : jsr lcd_instruction
    rts

; lcd_wait: poll busy flag (DB7) with RS=0,RW=1 until not busy
lcd_wait:
    pha
    lda #%00000000         : sta DDRB      ; PB inputs
@busy:
    lda #RW                 ; RS=0, RW=1
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
    and #%10000000         ; DB7 busy?
    bne @busy
    lda #%11111111         : sta DDRB      ; PB outputs
    pla
    rts

; lcd_get_addr: read current DDRAM address (7-bit) → A (clobbers X)
lcd_get_addr:
    lda DDRB
    pha
    lda #%00000000         : sta DDRB

    lda #RW                ; RS=0, RW=1 (address read)
    sta PORTA

    ; E HIGH
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR

    lda PORTB
    and #%01111111         ; mask address
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

; lcd_read_data: reads DDRAM data at current addr into A (clobbers Y)
lcd_read_data:
    jsr lcd_wait
    lda DDRB
    pha                     ; save DDRB on stack
    lda #$00
    sta DDRB

    lda #(RW | RS)          ; RS=1, RW=1 (data read)
    sta PORTA

    ; E HIGH
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_HIGH_BITS
    sta PCR
    lda PORTB              ; A = data
    tay                    ; hold in Y

    ; E LOW
    lda PCR
    and #PRESERVE_MASK
    ora #CB2_LOW_BITS
    sta PCR

    pla
    sta DDRB               ; restore DDRB
    tya                    ; A = data
    rts

; =============================================================================
; Backspace with shift (line-local)
; Preserves visible window edge behavior (pre-roll if at left edge).
; Cursor ends up one cell left of original pos.
; =============================================================================
lcd_backspace_shift:
    jsr lcd_get_addr
    tax                     ; X := AC (full 7-bit)
    tay                     ; Y := AC (full 7-bit)

    ; --- Pre-roll window if we're at the left edge of the visible window ---
    ; If (AC_low6 == WIN_OFF) and WIN_OFF > 0, scroll right once
    tya
    and #%00111111          ; absolute column 0..39
    sta tmp                 ; tmp := abs col
    lda WIN_OFF
    clc
    adc #1
    cmp tmp
    bne @no_preroll
    lda WIN_OFF
    beq @no_preroll
    dec WIN_OFF
    jsr shift_right_preserve_l2
@no_preroll:

    ; ---- compute line bit and (col-1), save final cursor target now ----
    txa
    and #%01000000
    sta tmp                  ; tmp = line bit (0x40)

    tya
    and #%00111111           ; Y := absolute column
    tay
    beq finish_backspace     ; at col 0: nothing to shift
    dey                      ; new cursor column := old-1

    tya
    ora tmp
    ora #CMD_SET_DDRAM
    sta BS_TARGET_ADDR       ; save final cursor DDRAM command

    tya
    tax                      ; X := starting src col (col-1)

copy_loop:
    cpx #LCD_LAST_COL
    bcs fill_last

    txa
    clc
    adc #1
    and #%00111111
    ora tmp
    ora #CMD_SET_DDRAM
    jsr lcd_instruction

    jsr lcd_read_data        ; A=data (clobbers Y)
    pha

    txa
    and #%00111111
    ora tmp
    ora #CMD_SET_DDRAM
    jsr lcd_instruction

    pla
    jsr print_char

    inx
    bra copy_loop

fill_last:
    lda #LCD_LAST_COL
    and #%00111111
    ora tmp
    ora #CMD_SET_DDRAM
    jsr lcd_instruction

    lda #' '
    jsr print_char

finish_backspace:
    lda BS_TARGET_ADDR
    jsr lcd_instruction
    rts

; =============================================================================
; One-step display shifts that preserve visible line 2
; =============================================================================
shift_left_preserve_l2:
    lda LAST_CURSOR_POS
    pha
    jsr lcd_get_addr
    sta LAST_CURSOR_POS

    lda #SHIFT_DISP_LEFT
    jsr lcd_instruction

    jsr show_insert_type_on_line2

    lda LAST_CURSOR_POS
    jsr reset_cursor
    pla
    sta LAST_CURSOR_POS
    rts

shift_right_preserve_l2:
    lda LAST_CURSOR_POS
    pha
    jsr lcd_get_addr
    sta LAST_CURSOR_POS

    lda #SHIFT_DISP_RIGHT
    jsr lcd_instruction

    jsr show_insert_type_on_line2

    lda LAST_CURSOR_POS
    jsr reset_cursor
    pla
    sta LAST_CURSOR_POS
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
+
    jsr show_current_mode_on_line2
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

    ; Enable CA1 interrupt (IER: bit1), write with bit7=1 to enable
    lda #%10000010
    sta IER
    rts

; =============================================================================
; Vectors
; =============================================================================
nmi: rti

* = $FFFA
!word nmi, reset, irq
