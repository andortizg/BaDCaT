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

; MSX-DOS file access through FCB calls (works on MSX-DOS 1 and 2)
    module Dos
BDOS    = 5
_FOPEN  = #0f
_FCLOSE = #10
_FMAKE  = #16
_SETDTA = #1a
_WRBLK  = #26
_RDBLK  = #27

; HL -> file name ("NAME.EXT" or "D:NAME.EXT"). Fills the FCB.
setName:
    push bc, de, hl
    ld de, fcb
    ld b, 37
    xor a
.clear
    ld (de), a : inc de
    djnz .clear
    ; drive letter?
    inc hl : ld a, (hl) : dec hl
    cp ':' : jr nz, .noDrive
    ld a, (hl) : call .upper
    sub 'A' - 1
    ld (fcb), a
    inc hl : inc hl
.noDrive
    ld de, fcb + 1
    ld b, 8
    call .part
    ld a, (hl) : cp '.' : jr nz, .ext
    inc hl
.ext
    ld de, fcb + 9
    ld b, 3
    call .part
    ; record size 1, random record 0
    ld hl, 1 : ld (fcb + 14), hl
    ld hl, 0 : ld (fcb + 33), hl, (fcb + 35), hl
    pop hl, de, bc
    ret
; Copies up to B characters (stops at '.' or end), pads with spaces
.part
    ld a, (hl) : and a : jr z, .pad
    cp '.' : jr z, .pad
    call .upper
    ld (de), a
    inc hl : inc de
    djnz .part
.skip
    ld a, (hl) : and a : ret z
    cp '.' : ret z
    inc hl
    jr .skip
.pad
    ld a, ' '
.padLoop
    ld (de), a : inc de
    djnz .padLoop
    ret
.upper
    cp 'a' : ret c
    cp 'z' + 1 : ret nc
    and #df
    ret

; Opens the file named with setName for reading. Z when found.
open:
    push bc, de, hl
    ld de, fcb
    ld c, _FOPEN
    call BDOS
    call .fix
    pop hl, de, bc
    and a
    ret
; _FOPEN overwrites the record size: restore it
.fix
    push af
    ld hl, 1 : ld (fcb + 14), hl
    ld hl, 0 : ld (fcb + 33), hl, (fcb + 35), hl
    pop af
    ret

; Creates (truncates) the file named with setName. Z when created.
create:
    push bc, de, hl
    ld de, fcb
    ld c, _FMAKE
    call BDOS
    call open.fix
    pop hl, de, bc
    and a
    ret

close:
    push af, bc, de, hl
    ld de, fcb
    ld c, _FCLOSE
    call BDOS
    pop hl, de, bc, af
    ret

; HL -> buffer, BC -> bytes to read. BC <- bytes read. Z when no error.
read:
    push de, hl
    ex de, hl
    ld c, _SETDTA
    call BDOS
    pop hl
    push hl
    ld h, b : ld l, c
    ld de, fcb
    ld c, _RDBLK
    call BDOS
    ld b, h : ld c, l
    pop hl, de
    and a
    ret

; HL -> buffer, BC -> bytes to write. Z when no error (NZ: disk full or write error)
write:
    push bc, de, hl
    ex de, hl
    ld c, _SETDTA
    call BDOS
    pop hl
    push hl
    ld h, b : ld l, c
    ld de, fcb
    ld c, _WRBLK
    call BDOS
    pop hl, de, bc
    and a
    ret

fcb ds 37

    endmodule
