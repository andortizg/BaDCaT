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
_CONST  = #0b
_BUFIN  = #0a
LINLEN  = #f3b0          ; current screen width (BIOS work area)

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

; Z when no key is waiting, NZ when one is (does not read it)
keyAvailable:
    push bc, de, hl
    ld c, _CONST
    call BDOS
    pop hl, de, bc
    and a
    ret

; Clears the screen (form feed)
cls:
    ld a, 12
    jp putC

; A <- screen width in columns
width:
    ld a, (LINLEN)
    ret

newLine:
    ld a, 13 : call putC
    ld a, 10 : jp putC

; A -> count of spaces (0 = none)
spaces:
    and a : ret z
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

; HL -> zero terminated string, B -> column width.
; Prints at most B characters and pads with spaces up to B.
putStringN:
    push bc, hl
.loop
    ld a, (hl) : and a : jr z, .pad
    call putC
    inc hl
    djnz .loop
    jr .end
.pad
    ld a, b : call spaces
.end
    pop hl, bc
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

; HL -> unsigned 16 bit value, B -> field width. Right aligned with spaces.
dispDec16W:
    push bc, de, hl
    ; count digits
    ld c, 1
    ld de, 10    : call .cmp
    ld de, 100   : call .cmp
    ld de, 1000  : call .cmp
    ld de, 10000 : call .cmp
    ld a, b : sub c
    jr c, .num
    call spaces
.num
    call dispDec16
    pop hl, de, bc
    ret
.cmp
    push hl
    and a : sbc hl, de
    pop hl
    ret c
    inc c
    ret

; A -> signed value to print in decimal
dispSigned:
    bit 7, a : jp z, dispA
    push af
    ld a, '-' : call putC
    pop af
    neg
    jp dispA

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
