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

    macro Print pointer
    ld hl, pointer : call Console.putStringZ
    endm

    module Console
BDOS = 5

; hl - ip addr
dispIP:
    dup 3
    ld a, (hl)
    call dispA
    push hl
    ld a, '.' : call putC
    pop hl
    inc hl
    edup
    ld a, (hl)
dispA:
	ld	c,-100
	call	.na1
	ld	c,-10
	call	.na1
	ld	c,-1
.na1	ld	b,'0'-1
.na2	inc	b
	add	a,c
	jr	c,.na2
	sub	c		;works as add 100/10/1
	push af		;safer than ld c,a
	ld	a,b		;char is in b
    push bc,de,hl
	call putC	;plot a char. Replace with bcall(_PutC) or similar.
    pop hl, de, bc
	pop af		;safer than ld a,c
	ret

newLine: 
    ld a, 13 : call putC
    ld a, 10
; A <- char
putC:
    ld e, a 
    ld c, 2
    jp BDOS

; HL <- String
putStringZ:
    ld a, (hl) : and a : ret z
    push hl : call putC : pop hl
    inc hl
    jr putStringZ

; HL - buffer
readString:
    ld (hl), 80
    ld de, hl
    push hl
    ld c, #0a
    call BDOS
    pop hl
    inc hl 
    ld a, (hl)
    inc a
    ld d, 0, e, a
    add hl, de
    xor a 
    ld (hl), a
    ret
    endmodule