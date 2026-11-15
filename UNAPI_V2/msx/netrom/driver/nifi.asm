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

; NiFi modem commands used by NETROM (firmware 0.3+)
    module Nifi

OP_Reset           = #00
OP_GET_FEATURES    = #01
OP_GET_IP          = #02
OP_GET_NETSTATE    = #03
OP_HTTP_LIST_URL   = #40
OP_HTTP_LIST_GET   = #41
OP_HTTP_LIST_ENTER = #42
OP_HTTP_LIST_UP    = #43
OP_HTTP_GET_ENTRY  = #44
OP_HTTP_GET_URL    = #45
OP_FILE_READ       = #46
OP_HTTP_LOCATION   = #47
OP_VERSION_STR     = #ff

IP_LOCAL = 1

ERR_OK          = 0
ERR_NOT_IMP     = 1
ERR_NO_NETWORK  = 2
ERR_NO_DATA     = 3
ERR_INV_PARAM   = 4
ERR_LARGE       = 14
ERR_INV_OPER    = 15
ERR_HTTP        = 17
ERR_BAD_ARCHIVE = 18
ERR_STORAGE     = 19
ERR_TIMEOUT     = 254      ; local: the modem did not answer in time
ERR_ABORTED     = 253      ; local: cancelled by the user

NETSTATE_OPEN = 2

; Reset attempts before giving up (each one waits about 10 frames per byte)
INIT_RETRIES = 40
; Frames to wait for the answer of a download / listing command (about 3 minutes)
LONG_WAIT = 10800

; Entry flags in listings
FLAG_DIR = 1

; Resets the modem and waits for the "NiFi" signature.
; Z (A = 0) when the modem answered, NZ (A = 1) when it did not.
init:
    call Uart.init
    ld c, INIT_RETRIES
.loop
    ld a, OP_Reset : call Uart.write
    call Uart.readTimeout : jr nc, .retry
    and a : jr nz, .flush
    call Uart.readTimeout : jr nc, .retry : cp 'N' : jr nz, .flush
    call Uart.readTimeout : jr nc, .retry : cp 'i' : jr nz, .flush
    call Uart.readTimeout : jr nc, .retry : cp 'F' : jr nz, .flush
    call Uart.readTimeout : jr nc, .retry : cp 'i' : jr nz, .flush
    call Uart.readTimeout : jr nc, .retry : and a  : jr nz, .flush
    xor a
    ret
.flush
    call Uart.readTimeout : jr c, .flush
.retry
    dec c : jr nz, .loop
    ld a, 1 : or a
    ret

; Reads a zero terminated string into (HL). HL <- after the terminator
readStr:
    call Uart.readB
    ld (hl), a
    inc hl
    and a : jr nz, readStr
    ret

; Reads a word into HL
readWord:
    call Uart.readB : push af
    call Uart.readB : ld h, a
    pop af : ld l, a
    ret

; HL -> buffer for the version string. A <- error
getVer:
    ld a, OP_VERSION_STR : call Uart.write
    call Uart.readB : and a : ret nz
    jp readStr

; A <- network state
getNetState:
    ld a, OP_GET_NETSTATE : call Uart.write
    call Uart.readB
    jp Uart.readB

; A -> IP enum. A <- error, HL DE <- address bytes 0-1 and 2-3
getIp:
    ld d, a
    ld a, OP_GET_IP : call Uart.write
    ld a, d : call Uart.write
    call Uart.readB : and a : ret nz
    call Uart.readB : ld l, a
    call Uart.readB : ld h, a
    call Uart.readB : ld e, a
    call Uart.readB : ld d, a
    xor a
    ret

; Waits for the first byte of a slow answer (listing / download).
; A <- error code, with (httpStatus) filled when it is ERR_HTTP.
; Returns ERR_TIMEOUT when the modem stays silent for LONG_WAIT frames.
waitResult:
    ld bc, LONG_WAIT
.wait
    call Uart.isAvailable : jr c, .got
    halt
    dec bc
    ld a, b : or c : jr nz, .wait
    ld a, ERR_TIMEOUT
    ret
.got
    call Uart.readB
    cp ERR_HTTP : ret nz
    push hl
    call readWord
    ld (httpStatus), hl
    pop hl
    ld a, ERR_HTTP
    ret

; Common tail of the listing commands: A <- error, DE <- entry count
listResult:
    call waitResult
    and a : ret nz
    push hl
    call readWord
    ex de, hl
    pop hl
    xor a
    ret

; HL -> URL (zero terminated). A <- error, DE <- entries
listUrl:
    ld a, OP_HTTP_LIST_URL : call Uart.write
    call Uart.writeString
    jr listResult

; DE -> index of a directory entry. A <- error, DE <- entries
listEnter:
    ld a, OP_HTTP_LIST_ENTER : call Uart.write
    ld a, e : call Uart.write
    ld a, d : call Uart.write
    jr listResult

; A <- error, DE <- entries
listUp:
    ld a, OP_HTTP_LIST_UP : call Uart.write
    jr listResult

; HL -> buffer for the current URL. A <- error
getLocation:
    ld a, OP_HTTP_LOCATION : call Uart.write
    call Uart.readB : and a : ret nz
    jp readStr

; Reads a page of the current listing.
; DE -> first matching entry to return, B -> entries wanted,
; HL -> filter (zero terminated, empty = all), IX -> destination buffer.
; A <- error, DE <- total matching entries, C <- entries stored.
; Buffer records: index (2), flags (1), size (4), name (zero terminated).
listGet:
    ld a, OP_HTTP_LIST_GET : call Uart.write
    ld a, e : call Uart.write
    ld a, d : call Uart.write
    ld a, b : call Uart.write
    call Uart.writeString
    call waitResult
    and a : ret nz
    call readWord : ex de, hl       ; DE = total matching
    call Uart.readB : ld c, a       ; C = entries returned
    push ix : pop hl
    ld b, c
    inc b : dec b : jr z, .done
.entry
    push bc
    ld b, 7                         ; index, flags, size
.fixed
    call Uart.readB : ld (hl), a : inc hl
    djnz .fixed
    call readStr
    pop bc
    djnz .entry
.done
    xor a
    ret

; Download commands. HL -> buffer for the file name (80 bytes).
; A <- error. On success (romSize) and (romCrc) are filled.
; DE -> index of a file entry
getEntry:
    ld a, OP_HTTP_GET_ENTRY : call Uart.write
    ld a, e : call Uart.write
    ld a, d : call Uart.write
    jr getResult
; HL -> URL (zero terminated), DE -> name buffer
getUrl:
    ld a, OP_HTTP_GET_URL : call Uart.write
    call Uart.writeString
    ex de, hl
getResult:
    call waitResult
    and a : ret nz
    push hl
    ld hl, romSize
    ld b, 8
.loop
    call Uart.readB : ld (hl), a : inc hl
    djnz .loop
    pop hl
    call readStr
    ; Reset the read position
    ld hl, 0
    ld (fileOff), hl, (fileOff + 2), hl
    xor a
    ret

; Reads the next block of the downloaded file at (fileOff).
; BC -> bytes wanted, HL -> destination.
; A <- error, BC <- bytes actually read (0 at the end of the file).
; (fileOff) advances by BC.
fileRead:
    push hl
    ld a, OP_FILE_READ : call Uart.write
    ld hl, fileOff
    ld a, (hl) : call Uart.write : inc hl
    ld a, (hl) : call Uart.write : inc hl
    ld a, (hl) : call Uart.write : inc hl
    ld a, (hl) : call Uart.write
    ld a, c : call Uart.write
    ld a, b : call Uart.write
    pop hl
    call Uart.readB : and a : ret nz
    push hl
    call readWord                   ; HL = length
    ld b, h : ld c, l
    ex de, hl                       ; DE = length
    pop hl
    ld a, b : or c : jr z, .advance
.data
    call Uart.readB : ld (hl), a : inc hl
    dec de
    ld a, d : or e : jr nz, .data
.advance
    push hl
    ld hl, (fileOff)
    add hl, bc
    ld (fileOff), hl
    jr nc, .ok
    ld hl, (fileOff + 2) : inc hl : ld (fileOff + 2), hl
.ok
    pop hl
    xor a
    ret

httpStatus dw 0
romSize    ds 4
romCrc     ds 4
fileOff    ds 4

    endmodule
