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

; This driver works with 16c550 uart that's support AFE
    module Uart
; Make init shorter and readable:-)
    macro outp port, value
    ld a, value
    out (port), a
    endm

; Internal port constants
RBR_THR = #80
IER     = RBR_THR + 1
IIR_FCR = RBR_THR + 2
LCR     = RBR_THR + 3
MCR     = RBR_THR + 4
LSR     = RBR_THR + 5
MSR     = RBR_THR + 6
SR      = RBR_THR + 7

init:
    outp MCR,     #0d  // Assert RTS
    outp IIR_FCR, #87  // Enable fifo 8 level, and clear it
    outp LCR,     #83  // 8n1, DLAB=1
    outp RBR_THR, #01  // 115200 (divider 1)
    outp IER,     #00  // (divider 0). Divider is 16 bit, so we get (#0002 divider)

    outp LCR,     #03 // 8n1, DLAB=0
    outp IER,     #00 // Disable int
    outp MCR,     #2f // Enable AFE
    ret
    
; Flag C <- Data available
isAvailable:
    in a, (LSR)
    rrca
    ret

; Non-blocking read
; Flag C <- is byte was readen
; A <- byte
read:
    in a, (LSR)
    rrca
    ret nc
    in a, (RBR_THR)
    scf 
    ret

; Tries read byte with timeout
; Flag C <- is byte read
; A <- byte
readTimeout:
    ld b, 10
.wait
    call isAvailable : jr c, read
    halt
    djnz .wait
    or a
    ret

; Blocking read
; A <- Byte
readB:
    in a, (LSR)
    rrca
    jr nc, readB
    in a, (RBR_THR)
    ret

; A -> byte to send
write:
    push af
.wait
    in a, (LSR)
    and #20
    jr z, .wait
    pop af
    out (RBR_THR), a
    ret

    endmodule