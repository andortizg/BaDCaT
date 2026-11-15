; NiFi UNAPI V2 - ESP8266 firmware, UNAPI driver and MSX-DOS tools
; for the BadCat WiFi cartridge.
;
; Copyright (C) 2026 Andrés Ortiz
; Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander
; Sharihin), Copyright (C) 2021, https://github.com/nihirash/esp-binary-firmware
;
; This program is free software: you can redistribute it and/or modify it
; under the terms of the GNU General Public License as published by the
; Free Software Foundation, either version 3 of the License, or (at your
; option) any later version.
;
; This program is distributed in the hope that it will be useful, but
; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
; for more details.
;
; You should have received a copy of the GNU General Public License along
; with this program. If not, see <https://www.gnu.org/licenses/>.
;
; SPDX-License-Identifier: GPL-3.0-or-later

; Console helpers on top of MSX-DOS BDOS calls.
; All routines preserve BC, DE and HL unless they return a value in them.
    macro Print pointer
    ld hl, pointer : call Console.putStringZ
    endm

    module Console
BDOS    = 5
_CONOUT = #02
_INNOE  = #08
_BUFIN  = #0a

KEY_BS  = 8
KEY_CR  = 13
KEY_ESC = 27
KEY_DEL = 127

; A -> char
putC:
    push bc, de, hl
    ld e, a
    ld c, _CONOUT
    call BDOS
    pop hl, de, bc
    ret

; A <- key (no echo)
getKey:
    push bc, de, hl
    ld c, _INNOE
    call BDOS
    pop hl, de, bc
    ret

newLine:
    ld a, 13 : call putC
    ld a, 10 : jp putC

; A -> count of spaces
spaces:
    push bc
    ld b, a
.loop
    ld a, ' ' : call putC
    djnz .loop
    pop bc
    ret

; HL -> zero terminated string
putStringZ:
    push hl
.loop
    ld a, (hl) : and a : jr z, .end
    call putC
    inc hl
    jr .loop
.end
    pop hl
    ret

; HL -> 4 bytes of an IP address
dispIP:
    push bc, hl
    ld b, 3
.loop
    ld a, (hl) : call dispA
    ld a, '.' : call putC
    inc hl
    djnz .loop
    ld a, (hl) : call dispA
    pop hl, bc
    ret

; A -> unsigned value to print in decimal (no leading zeros)
dispA:
    push bc, de, hl
    ld h, 0           ; H = 1 once a non-zero digit was printed
    ld c, 100 : call .digit
    ld c, 10  : call .digit
    add a, '0' : call putC
    pop hl, de, bc
    ret
.digit
    ld b, '0' - 1
.sub
    inc b
    sub c
    jr nc, .sub
    add a, c
    ld d, a
    ld a, b
    cp '0' : jr nz, .print
    bit 0, h : jr z, .skip
.print
    ld h, 1
    call putC
.skip
    ld a, d
    ret

; A -> unsigned value, printed right aligned in two columns
dispA2:
    cp 10 : jr nc, dispA
    push af
    ld a, ' ' : call putC
    pop af
    jr dispA

; A -> signed value to print in decimal
dispSigned:
    bit 7, a : jr z, dispA
    push af
    ld a, '-' : call putC
    pop af
    neg
    jr dispA

; A -> byte to print as two hex digits
dispHex:
    push af
    rrca : rrca : rrca : rrca
    call .nibble
    pop af
.nibble
    and #0f
    add a, '0'
    cp '9' + 1 : jp c, putC
    add a, 'A' - '0' - 10
    jp putC

; A -> RSSI (signed dBm, 0 = unknown). Prints a 6 char signal gauge "[****]"
dispBars:
    push bc
    ld b, 0
    and a : jr z, .print           ; unknown
    cp -80 : jr c, .print          ; weaker than -80 dBm: no bars
    inc b
    cp -70 : jr c, .print
    inc b
    cp -60 : jr c, .print
    inc b
    cp -50 : jr c, .print
    inc b
.print
    ld a, '[' : call putC
    ld c, 4
.loop
    ld a, ' '
    inc b : dec b : jr z, .put
    ld a, '*'
    dec b
.put
    call putC
    dec c : jr nz, .loop
    ld a, ']' : call putC
    pop bc
    ret

; HL -> buffer of at least B + 3 bytes, B -> maximum length
; Reads a line with editing (BDOS buffered input). The zero terminated
; text starts at HL + 2. Returns A = length.
readString:
    push bc, de, hl
    ld (hl), b
    inc hl : ld (hl), 0 : dec hl
    ex de, hl
    ld c, _BUFIN
    call BDOS
    pop hl
    push hl
    inc hl
    ld a, (hl)
    inc hl
    ld e, a
    ld d, 0
    add hl, de
    ld (hl), 0
    pop hl, de, bc
    ret

; HL -> buffer (zero terminated result), B -> maximum length
; Reads a line without echo, printing '*' for each character.
; Returns NC with A = length, or C when ESC was pressed (buffer emptied).
readPassword:
    push de, hl
    ld c, 0                 ; current length
    push hl
.loop
    call getKey
    cp KEY_CR  : jr z, .done
    cp KEY_ESC : jr z, .cancel
    cp KEY_BS  : jr z, .back
    cp KEY_DEL : jr z, .back
    cp ' '     : jr c, .loop
    ld d, a
    ld a, c : cp b : jr nc, .loop
    ld (hl), d
    inc hl
    inc c
    ld a, '*' : call putC
    jr .loop
.back
    ld a, c : and a : jr z, .loop
    dec hl
    dec c
    ld a, KEY_BS : call putC
    ld a, ' '    : call putC
    ld a, KEY_BS : call putC
    jr .loop
.done
    ld (hl), 0
    pop hl
    ld a, c
    and a
    pop hl, de
    ret
.cancel
    pop hl
    ld (hl), 0
    scf
    pop hl, de
    ret

; HL -> unsigned 16 bit value, printed in decimal without leading zeros
dispDec16:
    push bc, de, hl
    ld b, 0                 ; B = 1 once a digit was printed
    ld de, 10000 : call .digit
    ld de, 1000  : call .digit
    ld de, 100   : call .digit
    ld de, 10    : call .digit
    ld a, l : add a, '0' : call putC
    pop hl, de, bc
    ret
.digit
    ld c, '0' - 1
.sub
    inc c
    and a : sbc hl, de
    jr nc, .sub
    add hl, de
    ld a, c
    cp '0' : jr nz, .print
    inc b : dec b : ret z   ; leading zero
.print
    ld b, 1
    jp putC

; HL -> decimal string. A <- value (0..255, saturated), C flag when no digit found
parseDec:
    push bc, de, hl
    ld c, 0
    ld d, 0                 ; D = digits seen
.skip
    ld a, (hl) : cp ' ' : jr nz, .loop
    inc hl : jr .skip
.loop
    ld a, (hl)
    sub '0' : jr c, .end
    cp 10 : jr nc, .end
    ld e, a
    ld a, c
    cp 26 : jr nc, .sat
    add a, a : ld b, a      ; x2
    add a, a : add a, a     ; x8
    add a, b                ; x10
    add a, e
    jr c, .sat
    ld c, a
    inc d
    inc hl
    jr .loop
.sat
    ld c, 255
    inc d
.end
    ld a, c
    scf
    dec d : inc d : jr z, .exit
    ccf                     ; digits found: NC
.exit
    pop hl, de, bc
    ret

    endmodule
