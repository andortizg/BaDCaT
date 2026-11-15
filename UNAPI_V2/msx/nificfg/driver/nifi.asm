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

; NiFi modem commands used by the configuration utility
    module Nifi

OP_Reset          = #00
OP_GET_FEATURES   = #01
OP_GET_IP         = #02
OP_GET_NETSTATE   = #03
OP_GET_AP_LIST    = #30
OP_SET_AP         = #31
OP_GET_AP         = #32
OP_GET_RSSI       = #33
OP_GET_MAC        = #34
OP_FORGET_AP      = #35
OP_GET_AP_LIST_EX = #36
OP_OTA_CHECK      = #50
OP_OTA_UPDATE     = #51
OP_OTA_INFO       = #52
OP_OTA_BEGIN      = #53
OP_OTA_DATA       = #54
OP_OTA_END        = #55
OP_OTA_ABORT      = #56
OP_VERSION_STR    = #ff

IP_LOCAL   = 1
IP_REMOTE  = 2
IP_MASK    = 3
IP_GATEWAY = 4
IP_DNS1    = 5
IP_DNS2    = 6

ERR_OK          = 0
ERR_NOT_IMP     = 1
ERR_NO_NETWORK  = 2
ERR_AUTH_FAILED = 16
ERR_HTTP        = 17
ERR_UPDATE      = 20
ERR_TIMEOUT     = 254      ; local: the modem did not answer in time

; Frames to wait for the answer of an OTA command (about 3 minutes)
LONG_WAIT = 10800

NETSTATE_CLOSED  = 0
NETSTATE_OPENING = 1
NETSTATE_OPEN    = 2
NETSTATE_CLOSING = 3

; Reset attempts before giving up (each one waits about 10 frames per byte)
INIT_RETRIES = 40

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
    ; Unexpected byte: drop whatever is pending and try again
    call Uart.readTimeout : jr c, .flush
.retry
    dec c : jr nz, .loop
    ld a, 1 : or a
    ret

; Reads a zero terminated string into (HL)
; A <- error
_readString:
    call Uart.readB
    ld (hl), a
    inc hl
    and a : jr nz, _readString
    ret

; HL -> buffer for the version string
; A <- error
getVer:
    ld a, OP_VERSION_STR : call Uart.write
    call Uart.readB : and a : ret nz
    jr _readString

; HL -> buffer for the SSID
; A <- error (ERR_NO_NETWORK when not connected)
getAp:
    ld a, OP_GET_AP : call Uart.write
    call Uart.readB : and a : ret nz
    jr _readString

; A -> IP enum
; A <- error, HL DE <- address bytes 0-1 and 2-3
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

; A <- network state (NETSTATE_*)
getNetState:
    ld a, OP_GET_NETSTATE : call Uart.write
    call Uart.readB
    jp Uart.readB

; A <- error, C <- RSSI in dBm (signed)
getRssi:
    ld a, OP_GET_RSSI : call Uart.write
    call Uart.readB : and a : ret nz
    call Uart.readB : ld c, a
    xor a
    ret

; HL -> 6 byte buffer
; A <- error
getMac:
    ld a, OP_GET_MAC : call Uart.write
    call Uart.readB : and a : ret nz
    ld b, 6
.loop
    call Uart.readB : ld (hl), a : inc hl
    djnz .loop
    xor a
    ret

; A <- error
forgetAp:
    ld a, OP_FORGET_AP : call Uart.write
    jp Uart.readB

; HL -> SSID (zero terminated)
; DE -> password (zero terminated, empty for open networks)
; A <- error
setAp:
    ld a, OP_SET_AP : call Uart.write
    call Uart.writeString
    ex de, hl
    call Uart.writeString
    ex de, hl
    jp Uart.readB

; HL -> buffer for the list
; A <- error
; List format, one entry per network, strongest signal first:
;   SSID (zero terminated), RSSI (signed byte, 0 = unknown),
;   encryption (0 = open, 1 = secured, 2 = unknown)
; The list ends with #FF. Older firmware without the extended scan
; command is handled transparently (RSSI 0 and encryption 2).
getApList:
    ld a, OP_GET_AP_LIST_EX : call Uart.write
    call Uart.readB : and a : jr z, .read
    cp ERR_NOT_IMP : ret nz
    ; Old firmware: legacy list without signal/encryption information
    ld a, OP_GET_AP_LIST : call Uart.write
    call Uart.readB : and a : ret nz
.legacy
    call Uart.readB : cp #ff : jr z, .end
.lstr
    ld (hl), a : inc hl
    and a : jr z, .lfill
    call Uart.readB : jr .lstr
.lfill
    ld (hl), 0 : inc hl
    ld (hl), 2 : inc hl
    jr .legacy
.read
    call Uart.readB : cp #ff : jr z, .end
.str
    ld (hl), a : inc hl
    and a : jr z, .meta
    call Uart.readB : jr .str
.meta
    call Uart.readB : ld (hl), a : inc hl
    call Uart.readB : ld (hl), a : inc hl
    jr .read
.end
    ld (hl), #ff
    xor a
    ret

; Waits for the first byte of a slow answer. A <- error code; (httpStatus)
; is filled for ERR_HTTP and (updateMsg) for ERR_UPDATE.
; Returns ERR_TIMEOUT when the modem stays silent for LONG_WAIT frames.
waitResult:
    ld bc, LONG_WAIT
    call Uart.readFrames
    jr c, .got
    ld a, ERR_TIMEOUT
    ret
.got
    cp ERR_HTTP : jr z, .http
    cp ERR_UPDATE : ret nz
    push hl
    ld hl, updateMsg : call _readString
    pop hl
    ld a, ERR_UPDATE
    ret
.http
    push hl
    call Uart.readB : ld l, a
    call Uart.readB : ld h, a
    ld (httpStatus), hl
    pop hl
    ld a, ERR_HTTP
    ret

; HL -> URL of a small text file (version.txt), DE -> buffer for its first line
; A <- error
otaCheck:
    ld a, OP_OTA_CHECK : call Uart.write
    call Uart.writeString
    call waitResult
    and a : ret nz
    push hl
    ex de, hl : call _readString
    pop hl
    xor a
    ret

; HL -> URL of the firmware binary. A <- error (0 = flashed, the modem reboots)
otaUpdate:
    ld a, OP_OTA_UPDATE : call Uart.write
    call Uart.writeString
    jp waitResult

; HL -> 12 byte buffer (flash size, sketch size, free OTA space, 32 bit each),
; DE -> buffer for the version string. A <- error
otaInfo:
    ld a, OP_OTA_INFO : call Uart.write
    call Uart.readB : and a : ret nz
    push hl
    ld b, 12
.loop
    call Uart.readB : ld (hl), a : inc hl
    djnz .loop
    ex de, hl : call _readString
    pop hl
    xor a
    ret

; Firmware image sent from the host. DE HL -> image size (DE = high word)
; A <- error (ERR_UPDATE: description in (updateMsg))
otaBegin:
    ld a, OP_OTA_BEGIN : call Uart.write
    ld a, l : call Uart.write
    ld a, h : call Uart.write
    ld a, e : call Uart.write
    ld a, d : call Uart.write
    jp waitResult

; HL -> block, BC -> length. A <- error
otaData:
    ld a, OP_OTA_DATA : call Uart.write
    ld a, c : call Uart.write
    ld a, b : call Uart.write
    push hl, bc
.loop
    ld a, (hl) : call Uart.write
    inc hl
    dec bc
    ld a, b : or c : jr nz, .loop
    pop bc, hl
    jp waitResult

; A <- error (0 = image activated, the modem reboots)
otaEnd:
    ld a, OP_OTA_END : call Uart.write
    jp waitResult

otaAbort:
    ld a, OP_OTA_ABORT : call Uart.write
    jp waitResult

httpStatus dw 0
updateMsg  ds 128

    endmodule
