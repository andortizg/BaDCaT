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

    module Nifi
OP_Reset        = #00
OP_GET_IP       = #02
OP_GET_AP_LIST  = #30 
OP_SET_AP       = #31 
OP_GET_AP       = #32 
OP_VERSION_STR  = #ff 

IP_LOCAL = 1
IP_REMOTE = 2
IP_MASK = 3
IP_GATEWAY = 4
IP_DNS1 = 5

init:
    call Uart.init
.loop
    ld a, OP_Reset : call Uart.write
    call Uart.readTimeout : jr nc, .loop
.byteAvail
    and a : jr nz, .loop ; Check to success staus
    call Uart.readTimeout : jr nc, .loop : cp 'N' : jr nz, .loop
    call Uart.readTimeout : jr nc, .loop : cp 'i' : jr nz, .loop
    call Uart.readTimeout : jr nc, .loop : cp 'F' : jr nz, .loop
    call Uart.readTimeout : jr nc, .loop : cp 'i' : jr nz, .loop
    call Uart.readTimeout : jr nc, .loop : and a  : jr nz, .loop
    ; Success! :-) 
    ret

; A <- error
; HL <- buffer
getAp:
    ld a, OP_GET_AP : call Uart.write
    call Uart.readB : and a : ret nz
.loop
    call Uart.readB 
    ld (hl), a
    inc hl
    and a : jr nz, .loop
    ret

; A <- error
; HL <- buffer
getApList:
    ld a, OP_GET_AP_LIST : call Uart.write
    call Uart.readB : and a : ret nz
.loop
    call Uart.readB
    ld (hl), a
    inc hl
    cp #ff : jr nz, .loop
    xor a
    ret

; A - IP enum
getIp:
    ld d, a, a, OP_GET_IP : call Uart.write
    ld a, d : call Uart.write
    call Uart.readB : and a : ret nz
    jp _recvDWord


; HL <- SSID
; DE <- Password
; A -> Result
setAp:
    ld a, OP_SET_AP : call Uart.write
.ssid
    ld a, (hl) : call Uart.write
    and a : jr z, .pass
    inc hl
    jr .ssid
.pass
    ld a, (de) : call Uart.write
    and a : jr z, .exit
    inc de
    jr .pass
.exit
    call Uart.readB
    ret

getVer:
    ld a, OP_VERSION_STR : call Uart.write
    call Uart.readB : and a : ret nz
.loop
    call Uart.readB
    ld (hl), a
    inc hl
    and a : jr nz, .loop
    ret

; Internal procedure
; Reads from uart HL and DE
_recvDWord:
    call Uart.readB : ld l, a
    call Uart.readB : ld h, a
    call Uart.readB : ld e, a
    call Uart.readB : ld d, a
    xor a
    ret
    endmodule