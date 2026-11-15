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

;; UART FOR ZX-UNO
    module Uart
UART_DATA_REG = #c6
UART_STAT_REG = #c7
UART_BYTE_RECIVED = #80
UART_BYTE_SENDING = #40
SCANDBLCTRL_REG = #0B
ZXUNO_ADDR = #FC3B
ZXUNO_REG = #FD3B

; Enable UART
; Cleaning all flags by reading UART regs
; Wastes AF and BC
init:
    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    ld bc, ZXUNO_REG : in A, (c)
    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a
    ld bc, ZXUNO_REG : in A, (c)
    
    ld bc, #ffff
.loop
    push bc
    call readnb
    pop bc
    dec bc
    ld a, b : or c : jr nz, .loop
    ret

; Blocking read one byte
readb:
    call readnb : ret c
    jr readb

; Write single byte to UART
; A - byte to write
; BC will be wasted
write:
    push af

    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a

    ld bc, ZXUNO_REG : in A, (c) : and UART_BYTE_RECIVED
    jr nz,  .markRecv
.checkSent
    ld bc, ZXUNO_REG : in A, (c) : and UART_BYTE_SENDING
    jr nz, .checkSent

    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a

    ld bc, ZXUNO_REG : pop af : out (c), a
    ret
.markRecv:
    push af : push hl
    
    ld hl, is_recv : ld a, 1 : ld (hl), a 
    
    pop hl : pop af
    jr .checkSent

; Is data avail in UART
; NZ - Data Presents
; Z - Data absent
isAvail:
    ld a, (is_recv) : and 1 : ret nz
    ld a, (poked_byte) : and 1 : ret nz

    call readnb

    push af : ld a, b : and 1 : jr z, .nothing : pop af

    push af
    ld hl, byte_buff : ld (hl), a : ld hl, poked_byte : ld a, 1 : ld (hl), a
    pop af

    ld b, a : ld a, 1 : or a : ld a, b
    ret
.nothing
    pop bc : xor a
    ret

; Non blocking read byte from UART
; A: byte
; flag C - is data avail
readnb:
    ld a, (poked_byte) : and 1 : jr nz, .retBuff

    ld a, (is_recv) : and 1 : jr nz, .recvRet

    ld bc, ZXUNO_ADDR : ld a, UART_STAT_REG : out (c), a
    ld bc, ZXUNO_REG : in a, (c) : and UART_BYTE_RECIVED
    jr nz, .retReadByte

    or a
    ret
.retReadByte
    xor a : ld (poked_byte), a : ld (is_recv), a

    ld bc, ZXUNO_ADDR : ld a, UART_DATA_REG : out (c), a
    ld bc, ZXUNO_REG : in a, (c)

    scf
    ret
.recvRet
    ld bc, ZXUNO_ADDR : ld a,  UART_DATA_REG : out (c),a

    ld bc, ZXUNO_REG : in a, (c)
    ld hl, is_recv : ld (hl), 0
    ld hl, poked_byte : ld (hl), 0
    
    scf
    ret

.retBuff
    ld a, 0 : ld (poked_byte), a : ld a, (byte_buff)
    scf
    ret

poked_byte defb 0
byte_buff defb 0
is_recv defb 0

    endmodule












