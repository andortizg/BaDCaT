; NiFi UNAPI V2 - ESP8266 firmware, UNAPI driver and MSX-DOS tools
; for the BadCat WiFi cartridge.
;
; Copyright (C) 2026 Andrés Ortiz
; Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander
; Sharihin), Copyright (C) 2021, https://github.com/nihirash/esp-binary-firmware
;
; The UART type detection and the software flow control for the 16C550
; without AFE follow the approach of the 16C550CZiModem library by
; Oduvaldo Pavan Junior (ducasp), Copyright (C) 2020,
; https://github.com/ducasp/MSX-Development
; (re-implemented for the NiFi protocol, no code was copied).
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

; 16C550 UART driver for the NiFi modem (BadCat cartridge and compatibles).
;
; Two flavours of the cartridge exist: with a 16C550C, whose automatic flow
; control (AFE) drives RTS/CTS in hardware, and with a plain 16C550, where
; the flow control has to be done by software. init identifies the chip and
; selects the mode; the rest of the API is the same for both.
;
; Software mode mirrors what the modem does on its side (it raises RTS only
; while it waits for a byte and checks CTS before every byte it sends):
;  * RTS is raised only while a read routine waits for a byte and dropped
;    as soon as the byte arrives, so at most one extra byte can be in the
;    FIFO when the MSX is busy (interrupts, disk, screen): nothing is lost
;  * before sending a byte, CTS is checked (with a timeout, in case the
;    line is not wired)
;
; Change UART_BASE if your cartridge maps the chip at another I/O port.
; This file is shared by the UNAPI driver, NIFICFG and NETROM: keep the
; copies identical.
    module Uart

UART_BASE = #80

    macro outp port, value
    ld a, value
    out (port), a
    endm

; Internal port constants
RBR_THR = UART_BASE
IER     = RBR_THR + 1
IIR_FCR = RBR_THR + 2
LCR     = RBR_THR + 3
MCR     = RBR_THR + 4
LSR     = RBR_THR + 5
MSR     = RBR_THR + 6
SR      = RBR_THR + 7

; MCR values (bit 1 = RTS, bit 5 = AFE; DTR / OUT1 / OUT2 always set)
MCR_STOP = #0d       ; RTS inactive: the modem must not send
MCR_GO   = #0f       ; RTS active: the modem may send
MCR_AFE  = #2f       ; RTS active, automatic flow control

; UART types returned by detect / stored in (type)
TYPE_16C550C = 0     ; FIFO and automatic flow control (AFE)
TYPE_16C550  = 1     ; FIFO, no AFE: software flow control
TYPE_16C450  = 2     ; no FIFO: software flow control
TYPE_NONE    = 3     ; nothing answers at UART_BASE

; Loops waiting for CTS before sending a byte (about one second)
CTS_TIMEOUT = 40000

; Identifies the chip at UART_BASE. A <- TYPE_* (also stored in (type)).
; Scratch register test, then FIFO test (IIR bits 7-6 after enabling the
; FIFO) and AFE test (bit 5 of MCR can only be set on a 16C550C/16C750).
detect:
    ld a, #5a : out (SR), a
    in a, (SR) : cp #5a : jr nz, .none
    ld a, #a5 : out (SR), a
    in a, (SR) : cp #a5 : jr nz, .none
    outp IIR_FCR, #07
    in a, (IIR_FCR)
    and #c0 : cp #c0 : jr nz, .noFifo
    outp MCR, #22
    in a, (MCR)
    and #20 : jr z, .noAfe
    xor a
    jr .done
.noAfe
    ld a, TYPE_16C550
    jr .done
.noFifo
    ld a, TYPE_16C450
    jr .done
.none
    ld a, TYPE_NONE
.done
    ld (type), a
    ret

; Identifies the chip and configures it: 115200 bps, 8N1, FIFO, no interrupts.
; A <- UART type
init:
    call detect
    outp MCR,     MCR_STOP
    outp IIR_FCR, #87  // Enable fifo 8 level, and clear it
    outp LCR,     #83  // 8n1, DLAB=1
    outp RBR_THR, #01  // 115200 (divider 1)
    outp IER,     #00  // (divider high byte)
    outp LCR,     #03  // 8n1, DLAB=0
    outp IER,     #00  // Disable int
    ld a, (type)
    and a : jr nz, .soft
    outp MCR, MCR_AFE  // Hardware flow control
    xor a
    ret
.soft
    outp MCR, MCR_STOP // Software flow control: RTS raised only while reading
    ld a, (type)
    ret

; Z when the UART does the flow control itself (AFE)
isAfe:
    ld a, (type)
    and a
    ret

; Raise / drop RTS (no-ops in AFE mode). Modify A only.
rxOn:
    ld a, (type) : and a : ret z
    ld a, MCR_GO : out (MCR), a
    ret
rxOff:
    ld a, (type) : and a : ret z
    ld a, MCR_STOP : out (MCR), a
    ret

; Flag C <- Data available (does not touch RTS)
isAvailable:
    in a, (LSR)
    rrca
    ret

; Non-blocking read (does not touch RTS)
; Flag C <- a byte was read, A <- byte
read:
    in a, (LSR)
    rrca
    ret nc
    in a, (RBR_THR)
    scf
    ret

; Waits up to BC frames for a byte (interrupts must be enabled).
; Flag C <- a byte was read, A <- byte. Preserves BC, DE, HL.
readFrames:
    push bc
    call rxOn
.wait
    in a, (LSR)
    rrca : jr c, .got
    halt
    dec bc
    ld a, b : or c : jr nz, .wait
    call rxOff
    pop bc
    or a
    ret
.got
    in a, (RBR_THR)
    ld b, a
    call rxOff
    ld a, b
    pop bc
    scf
    ret

; Tries to read a byte with a short timeout (about 10 frames)
; Flag C <- a byte was read, A <- byte. Preserves BC, DE, HL.
readTimeout:
    push bc
    ld bc, 10
    call readFrames
    pop bc
    ret

; Blocking read. A <- byte. Preserves BC, DE, HL.
readB:
    call rxOn
.wait
    in a, (LSR)
    rrca
    jr nc, .wait
    in a, (RBR_THR)
    push af
    call rxOff
    pop af
    ret

; Blocking read word. HL <- word
readBHL:
    call readB : ld l, a
    call readB : ld h, a
    ret

; Blocking read double word. HLDE <- 4 bytes (HL first)
readBHLDE:
    call readB : ld l, a
    call readB : ld h, a
    call readB : ld e, a
    call readB : ld d, a
    ret

; A -> byte to send. Preserves all registers.
write:
    push af
    ld a, (type) : and a : jr z, .thre
    ; Software flow control: wait for CTS (MSR bit 4), with a timeout
    push bc
    ld bc, CTS_TIMEOUT
.cts
    in a, (MSR)
    bit 4, a : jr nz, .ctsOk
    dec bc
    ld a, b : or c : jr nz, .cts
.ctsOk
    pop bc
.thre
    in a, (LSR)
    and #20
    jr z, .thre
    pop af
    out (RBR_THR), a
    ret

; HL -> zero terminated string to send (terminator included)
writeString:
    ld a, (hl) : call write
    and a : ret z
    inc hl
    jr writeString

; HL -> word to send (low byte first)
writeHL:
    ld a, l : call write
    ld a, h : jp write

type db TYPE_NONE

    endmodule
