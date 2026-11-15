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
OP_GET_FEATURES = #01
OP_GET_IP       = #02
OP_GET_NETSTATE = #03
OP_RESOLVE_DNS  = #06
OP_OPEN_UDP     = #08 
OP_CLOSE_UDP    = #09 
OP_STATUS_UDP   = #0A 
OP_SEND_DATAGR  = #0B 
OP_RECV_DATAGR  = #0C 
OP_OPEN_TCP     = #0D 
OP_CLOSE_TCP    = #0E 
OP_STATUS_TCP   = #10 
OP_SEND_TCP     = #11 
OP_RECV_TCP     = #12 
OP_CONF_AUTO_IP = #19 
OP_CONF_IP      = #1A 
OP_GET_AP_LIST  = #30 
OP_SET_AP       = #31 
OP_GET_AP       = #32 
OP_VERSION_STR  = #ff 

IP_LOCAL = 1
IP_REMOTE = 2
IP_MASK = 3
IP_GATEWAY = 4
IP_DNS1 = 5
IP_DNS2 = 6

NETSTATE_CLOSED = 0
NETSTATE_OPENING = 1
NETSTATE_OPEN = 2
NETSTATE_CLOSING = 3
NETSTATE_UNKNOWN = 255

CONN_STATE_UNKNOWN = 0     ; Read like "closed"
CONN_STATE_ESTABLISHED = 4 ; Really we don't care about other statuses    

;; Tries init ESP. Sending zero and waiting for magic string
init:
    call Uart.init
.loop
    ld a, OP_Reset : call Uart.write
    ld d, #16
.waitForResponse
    call Uart.readnb : jr c, .byteAvail
    dec d : jr nz, .waitForResponse
    jr .loop
.byteAvail
    or a  : jr nz, .loop
    call Uart.readb : cp 'N' : jr nz, .loop
    call Uart.readb : cp 'i' : jr nz, .loop
    call Uart.readb : cp 'F' : jr nz, .loop
    call Uart.readb : cp 'i' : jr nz, .loop
    call Uart.readb : and a  : jr nz, .loop
    ret

; HL - buffer for response
getVer:
    push hl
    ld a, OP_VERSION_STR : call Uart.write
    call Uart.readb 
    pop hl
.loop
    push hl : call Uart.readb : pop hl : ld (hl), a : and a : ret z
    inc hl
    jr .loop

;;;;;;;;;;;;;;;;;;; Networking functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; A - IP_TYPE
; flag NZ - error(error in A)
; L.H.E.D - IP group
getIp:
    ld d, a
    ld a, OP_GET_IP : call Uart.write
    ld a,d : call Uart.write
    call Uart.readb : and a : ret nz
    call _recvDWord
    xor a
    ret

; In A will be netstate(see constants)
getNetState:
    ld a, OP_GET_NETSTATE : call Uart.write
    call Uart.readb : and a : ret nz
    jp Uart.readb

; DE - buffer
; NZ - error
getAp:
    ld a, OP_GET_AP : call Uart.write
    call Uart.readb : and a : ret nz 
.loop
    call Uart.readb : ld (de), a : inc de
    and a : ret z
    jp .loop

; HL - SSID
; DE - Password
; NZ - error flag
setAp:
    push de, hl
    ld a, OP_SET_AP : call Uart.write
    pop de
.loop
    ld a, (de)
    push af : call Uart.write : pop af
    and a : jr z, .passSend
    jr .loop
.passSend
    pop de
.loop2
    ld a, (de)
    push af : call Uart.write : pop af
    and a : jr z, .result
    jr .loop2
.result
    call Uart.readb : and a
    ret

; DE - buffer. AP sepparated by zeros finished with #FF byte
getApList:
    ld a, OP_GET_AP_LIST : call Uart.write
    call Uart.readb : and a : ret nz
.loop
    call Uart.readb 
    ld (de), a : inc de
    cp #ff : ret z
    jr .loop

; HL - domain string
; NZ - error flag
; IP will be in L.H.E.D
resolveDns:
    ld a, OP_RESOLVE_DNS : call Uart.write
.loop
    ld a, (hl) : call Uart.write
    and a : jr z, .response
    inc hl
    jr .loop
.response
    call Uart.readb : and a : ret nz
    call _recvDWord
    xor a
    ret

;;;;;;;;;;;;;;;;;;;;;;;; TCP ;;;;;;;;;;;;;;;;;;;;;;;;;;

; BC - port
; L.H.E.D - IP addr
; NZ - error flag
; A - socket id or error
openTcp:
    ld (.buff), hl, (.buff + 2), de, (.buff + 4), bc
    ld a, OP_OPEN_TCP : call Uart.write

    ld hl, .buff
    dup 6
    ld a, (hl) : push hl : call Uart.write : pop hl : inc hl
    edup
    call Uart.readb : and a : ret nz
    call Uart.readb : ld b, a : xor a : ld a, b
    ret
.buff ds 6

; A - socket
; A - result
closeTcp:
    ld d, a
    ld a, OP_CLOSE_TCP : call Uart.write
    ld a, d : call Uart.write
    call Uart.readb : and a
    ret

; A - socket
; NZ - error flag
; A - error or status
; BC - avail data
statusTcp:    
    ld d, a 
    ld a, OP_STATUS_TCP : call Uart.write
    ld a, d : call Uart.write
    call Uart.readb : and a : ret nz

    call Uart.readb : ld (.status + 1), a
    call Uart.readb : ld (.avail + 1), a
    call Uart.readb : ld (.avail + 2), a 
    
    xor a 
.status
    ld a, 4
.avail
    ld bc, 0
    ret

; A - socket
; HL - buffer
; BC - size
; NZ - error flag
writeTcp:
    ex af, af
    ld a, b : or c : ret z ; Are you serious?
    ex af, af
    ld (tcpBuff.socket), a, (tcpBuff.pointer), hl, (tcpBuff.size), bc
    ld a, OP_SEND_TCP : call Uart.write
    ld hl, tcpBuff
    dup 3
    ld a, (hl) : call Uart.write : inc hl
    edup
    call Uart.readb : and a : ret nz
    ld hl, (tcpBuff.pointer)
    ld bc, (tcpBuff.size)
.loop
    push hl, bc
    ld a, (hl) : call Uart.write
    pop bc, hl
    dec bc
    inc hl
    ld a, b : or c : jr nz, .loop
    ret


; A - socket
; HL - buffer
; BC - size
;
; NZ - error flag
; BC - actual data size
readTcp:
    ld (tcpBuff.socket), a, (tcpBuff.pointer), hl, (tcpBuff.size), bc
    ld a, OP_RECV_TCP : call Uart.write
    ld hl, tcpBuff
    dup 3
    ld a, (hl) : push hl : call Uart.write : pop hl : inc hl
    edup
    call Uart.readb : and a : ret nz
    ;; Reading actual data size
    call Uart.readb : ld (tcpBuff.size), a
    call Uart.readb : ld (tcpBuff.size + 1), a
    ld hl, (tcpBuff.pointer), bc, (tcpBuff.size)
    ld a, b : or c : ret z 
.loop
    push bc, hl
    call Uart.readb : ld (hl), a 
    pop hl, bc
    dec bc
    inc hl
    ld a, b : or c : jr nz, .loop
    ld bc, (tcpBuff.size)
    ret

tcpBuff:
.socket  db 0
.size    dw 0
.pointer dw 0

;;;;;;;;;;;;;;;;;;;;;;;; TCP ;;;;;;;;;;;;;;;;;;;;;;;;;;

; DE - port
; NZ - error(error code in A)
; A - connection id
openUDP:
    ld a, OP_OPEN_UDP : call Uart.write
    ld a, e : call Uart.write
    ld a, d : call Uart.write
    call Uart.readb : and a : ret nz
    call Uart.readb : ld d, a
    xor a
    ld a, d
    ret

; A - connection id
closeUDP:
    ld d, a
    ld a, OP_CLOSE_UDP : call Uart.write
    ld a, d : call Uart.write
    call Uart.readb : and a 
    ret

; A - connection id
; NZ - error flag(error in A)
; HL - port
; BC - avail. byte count
statusUDP:
    ld d, a
    ld a, OP_STATUS_UDP : call Uart.write
    ld a, d : call Uart.write
    call Uart.readb : and a : ret nz
    call Uart.readb : ld l, a ; Port
    call Uart.readb : ld h, a
    call Uart.readb : ld c, a ; Avail. data
    call Uart.readb : ld b, a
    xor a
    ret

;;;;;;;;;; SERVICE ROUTINES ;;;;;;;;;;;;;;;;;;;;;;

; Internal procedure
; Reads from uart HL and DE
_recvDWord:
    call Uart.readb : ld l, a
    call Uart.readb : ld h, a
    call Uart.readb : ld e, a
    call Uart.readb : ld d, a
    ret
    endmodule

