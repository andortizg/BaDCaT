; NiFi UNAPI V2 - ESP8266 firmware, UNAPI driver and MSX-DOS tools
; for the BadCat WiFi cartridge.
;
; Copyright (C) 2026 Andrés Ortiz
; Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander
; Sharihin), Copyright (C) 2021, https://github.com/nihirash/esp-binary-firmware
;
; The UNAPI driver is based on the driver for custom ESP firmware by
; Oduvaldo Pavan Junior (ducasp), Copyright (C) 2020, used as skeleton
; by Nihirash: https://github.com/ducasp/MSX-Development
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

; Device constants
OP_Reset          = #00
OP_GET_FEATURES   = #01
OP_GET_IP         = #02
OP_GET_NETSTATE   = #03
OP_RESOLVE_DNS    = #06
OP_OPEN_UDP       = #08 
OP_CLOSE_UDP      = #09 
OP_STATUS_UDP     = #0A 
OP_SEND_DATAGR    = #0B 
OP_RECV_DATAGR    = #0C 
OP_OPEN_TCP       = #0D 
OP_CLOSE_TCP      = #0E 
OP_STATUS_TCP     = #10 
OP_SEND_TCP       = #11 
OP_RECV_TCP       = #12 
OP_EXT_STATUS_TCP = #13
OP_OPEN_TCP_EX    = #14 ; UNAPI parameter block (active and passive)
OP_ABORT_TCP      = #15
OP_CONF_AUTO_IP   = #19
OP_CONF_IP        = #1A 
OP_GET_AP_LIST    = #30 
OP_SET_AP         = #31 
OP_GET_AP         = #32 
OP_VERSION_STR    = #ff 

IP_LOCAL   = 1
IP_REMOTE  = 2
IP_MASK    = 3
IP_GATEWAY = 4
IP_DNS1    = 5
IP_DNS2    = 6

NETSTATE_CLOSED  = 0
NETSTATE_OPENING = 1
NETSTATE_OPEN    = 2
NETSTATE_CLOSING = 3
NETSTATE_UNKNOWN = 255

; GET_FEATURES blocks
BLOCK_CAP_FLAGS   = 1
BLOCK_POOL_SIZE   = 2
BLOCK_MAX_FRAME   = 3
BLOCK_CAP_FLAGS2  = 4
BLOCK_FEATURES    = 5 ; NiFi extension: features flags + link level protocol

; Used only when the firmware does not answer BLOCK_FEATURES (older firmware)
FEATURES_DEFAULT  = %0000110000000010 ; Wireless, DNS_Q blocking, TCP_OPEN blocking
LINK_WIFI         = 4

CONN_STATE_UNKNOWN     = 0 ; Read like "closed"
CONN_STATE_LISTEN      = 1
CONN_STATE_ESTABLISHED = 4
CONN_STATE_CLOSE_WAIT  = 7

    macro publishByte what
    ld a, what : call Uart.write
    endm


;*********************************************
;***  CODE TO BE INSTALLED ON RAM SEGMENT  ***
;*********************************************

SEG_CODE:
	org	#4000
SEG_CODE_START:

;===============================
;===  HTIM_I hook execution  ===
;===============================
DO_HTIMI:
	push	af						; HTIM hook -> need to keep A value
	ld	hl,(TIMEOUT_COUNTER)
	ld	a,l
	or	h							; In this operation, check if HL is o
	jr	z,DO_HTIMI_END				; If it is, nothing to do
	dec	hl							; Otherwise decrement it
	ld	(TIMEOUT_COUNTER),hl		; And save it
DO_HTIMI_END:
	pop	af							; Restore original A value
	jp	OLD_HTIM_I					; And do whatever was in the hook before
	nop
	nop								; place holders to have DO_EXTBIO in 4012

;>>> Note that this code starts exactly at address #4012 / Index 6
; If HTIM function changes, might need to adjust index for this
;===============================
;===  EXTBIO hook execution  ===
;===============================
DO_EXTBIO:
	push	hl
	push	bc
	push	af
	ld	a,d
	cp	#22
	jr	nz,JUMP_OLD
	cp	e
	jr	nz,JUMP_OLD

	; Check API ID
	ld	hl,UNAPI_ID
	ld	de,ARG
LOOP:
	ld	a,(de)
	call TOUPPER
	cp	(hl)
	jr	nz,JUMP_OLD2
	inc	hl
	inc	de
	or	a
	jr	nz,LOOP

	; A=255: Jump to old hook

	pop	af
	push	af
	inc	a
	jr	z,JUMP_OLD2

	; A=0: B=B+1 and jump to old hook

	pop	af
	pop	bc
	or	a
	jr	nz,DO_EXTBIO2
	inc	b
	pop	hl
	ld	de,#2222
	jp	OLD_EXTBIO
DO_EXTBIO2:

	; A=1: Return A=Slot, B=Segment, HL=UNAPI entry address

	dec	a
	jr	nz,DO_EXTBIO3
	pop	hl
	ld	a,(MY_SEG)
	ld	b,a
	ld	a,(MY_SLOT)
	ld	hl,UNAPI_ENTRY
	ld	de,#2222
	ret

	; A>1: A=A-1, and jump to old hook

DO_EXTBIO3:							; A=A-1 already done
	pop	hl
	ld	de,#2222
	jp	OLD_EXTBIO


;--- Jump here to execute old EXTBIO code

JUMP_OLD2:
	ld	de,#2222
JUMP_OLD:							; Assumes "push hl,bc,af" done
	pop	af
	pop	bc
	pop	hl
; Old EXTBIO hook contents is here
; (it is setup at installation time)
OLD_EXTBIO:				ds	5
;Old HTIM_I hook contents is here
;(it is setup at installation time)
OLD_HTIM_I:				ds	5

;====================================
;===  Functions entry point code  ===
;====================================
UNAPI_ENTRY:
	ei
	push	hl
	push	af
	ld	hl,FN_TABLE
	bit	7,a

	if	MAX_IMPFN >= 128

	jr	z,IS_STANDARD
	ld	hl,IMPFN_TABLE
	and	%01111111
	cp	MAX_IMPFN-128
	jr	z,OK_FNUM
	jr	nc,UNDEFINED
IS_STANDARD:

	else

	jr	nz,UNDEFINED

	endif

	cp	MAX_FN
	jr	z,OK_FNUM
	jr	nc,UNDEFINED

OK_FNUM:
	add	a,a
	push	de
	ld	e,a
	ld	d,0
	add	hl,de
	pop	de

	ld	a,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,a

	pop	af
	ex	(sp),hl
	ret

;--- Undefined function: return with registers unmodified
UNDEFINED:
	pop	af
	pop	hl
	ret


;===================================
;===  Functions addresses table  ===
;===================================

;--- Implementation-specific routines addresses table

	if	MAX_IMPFN >= 128

IMPFN_TABLE:
FN_128:					dw	FN_DUMMY

	endif

FN_TABLE:
FN_0:					dw	UNAPI_GET_INFO
FN_1:					dw	TCPIP_GET_CAPAB
FN_2:					dw	TCPIP_GET_IPINFO
FN_3:					dw	TCPIP_NET_STATE
FN_4:					dw	FN_NOT_IMP ;TCPIP_SEND_ECHO not going to be implemented, ESP do not support ping like UNAPI specify
FN_5:					dw	FN_NOT_IMP ;TCPIP_RCV_ECHO not going to be implemented as SEND_ECHO is not implemented
FN_6:					dw	TCPIP_DNS_Q
FN_7:					dw	TCPIP_DNS_S
FN_8:					dw	TCPIP_UDP_OPEN
FN_9:					dw	TCPIP_UDP_CLOSE
FN_10:					dw	TCPIP_UDP_STATE
FN_11:					dw	TCPIP_UDP_SEND
FN_12:					dw	TCPIP_UDP_RCV
FN_13:					dw	TCPIP_TCP_OPEN
FN_14:					dw	TCPIP_TCP_CLOSE
FN_15:					dw	TCPIP_TCP_ABORT
FN_16:					dw	TCPIP_TCP_STATE
FN_17:					dw	TCPIP_TCP_SEND
FN_18:					dw	TCPIP_TCP_RCV
FN_19:					dw	FN_NOT_IMP ;TCPIP_TCP_DISCARD: data is sent synchronously by the ESP, there is no output buffer to discard (capability bit 9 is not set)
FN_20:					dw	FN_NOT_IMP ;TCPIP_RAW_OPEN not going to be implemented, ESP do not support RAW connections
FN_21:					dw	FN_NOT_IMP ;TCPIP_RAW_CLOSE not going to be implemented, ESP do not support RAW connections
FN_22:					dw	FN_NOT_IMP ;TCPIP_RAW_STATE not going to be implemented, ESP do not support RAW connections
FN_23:					dw	FN_NOT_IMP ;TCPIP_RAW_SEND not going to be implemented, ESP do not support RAW connections
FN_24:					dw	FN_NOT_IMP ;TCPIP_RAW_RCV not going to be implemented, ESP do not support RAW connections
FN_25:					dw	FN_NOT_IMP
FN_26:					dw	FN_NOT_IMP
FN_27:					dw	FN_NOT_IMP
FN_28:					dw	FN_NOT_IMP
FN_29:					dw	END_OK ;TCPIP_WAIT not needed for our implementation


;========================
;===  Functions code  ===
;========================
FN_NOT_IMP:
	ld	a,ERR_NOT_IMP
	ret

END_OK:	
	xor a
	ret

UNAPI_GET_INFO:
	ld	a,(ROM_V_P)
	ld	b,a
	ld	a,(ROM_V_S)
	ld	c,a
	ld	de,256*API_V_P+API_V_S
	ld	hl,APIINFO
	xor	a
	ret

TCPIP_GET_CAPAB:
    ; The firmware validates the block index itself
    publishByte OP_GET_FEATURES
    ld a, b : call Uart.write
    call Uart.readB : and a : ret nz ; Error code already in A

    ld a, b
    cp BLOCK_CAP_FLAGS  : jr z, .block1
    cp BLOCK_POOL_SIZE  : jr z, .block2
    cp BLOCK_MAX_FRAME  : jr z, .block3
    cp BLOCK_CAP_FLAGS2 : jr z, .block4
    ld a, ERR_INV_PARAM
	ret
.block1
    ; HL = capabilities (from the firmware)
    call Uart.readBHL
    push hl
    ; DE = features flags, B = link level protocol (from the firmware when available)
    publishByte OP_GET_FEATURES
    ld a, BLOCK_FEATURES : call Uart.write
    call Uart.readB : and a : jr nz, .block1def
    call Uart.readB : ld e, a
    call Uart.readB : ld d, a
    call Uart.readB : ld b, a
    pop hl
    xor a
    ret
.block1def
    pop hl
    ld de, FEATURES_DEFAULT
    ld b, LINK_WIFI
    xor a
    ret
.block2
    call Uart.readB : ld b, a
    call Uart.readB : ld c, a
    call Uart.readB : ld d, a
    call Uart.readB : ld e, a
    xor a : ld l, a, h, a ; RAW IP not supported :(
    ret
.block3
    call Uart.readBHLDE
    xor a
    ret
.block4
    ; HL = second capabilities word, DE = second features word
    call Uart.readBHL
    ex de, hl
    call Uart.readBHL
    ex de, hl
    xor a
    ret

TCPIP_GET_IPINFO:
    publishByte OP_GET_IP
    ld a, b : call Uart.write
    call Uart.readB : and a : ret nz
    call Uart.readBHLDE
    xor a
    ret

TCPIP_NET_STATE:
    publishByte OP_GET_NETSTATE
    call Uart.readB
    call Uart.readB : ld b, a
    xor a 
    ret

TCPIP_DNS_Q:
    publishByte OP_RESOLVE_DNS
    call Uart.writeString
    call Uart.readB 
    ld (DNS.err), a : and a : ret nz

    call Uart.readBHLDE
    ld (DNS.res), hl, (DNS.res + 2), de
    
    xor a : ld b, a : ld (DNS.err), a
    ret

DNS:
.err db 0
.res ds 4

TCPIP_DNS_S:
    ld hl, (DNS.res)
    ld de, (DNS.res + 2)
    ld a, (DNS.err)
    push af, de, hl
    ld a, b : and 1 : jr z, .exit
    xor a : ld hl, DNS, de, DNS + 1, bc, 4, (hl), a : ldir
.exit
    pop hl, de, af
    ld b, 2, c, 0
    ret

TCPIP_UDP_OPEN:
    publishByte OP_OPEN_UDP
    call Uart.writeHL
    call Uart.readB : and a : ret nz
    call Uart.readB : ld b, a : xor a
    ret

TCPIP_UDP_CLOSE:
    publishByte OP_CLOSE_UDP
    ld a, b : call Uart.write
    jp Uart.readB

TCPIP_UDP_STATE:
    publishByte OP_STATUS_UDP
    ld a, b : call Uart.write
    call Uart.readB : and a : ret nz
    call Uart.readBHL
    ex de, hl
    call Uart.readBHL
    ex de, hl
    ld b, 0
    ld a, d : or e : jr z, .skip
    ld b, 1
.skip
    xor a
    ret

TCPIP_UDP_SEND:
    ld (.addr + 1), hl
    ld (.blockad + 1), de 

    publishByte OP_SEND_DATAGR ; Command
    ld a, b : call Uart.write  ; Socket ID

    dup 8
    ld a, (de) : call Uart.write
    inc de
    edup
    call Uart.readB : and a : ret nz

.blockad
    ld de, 0

    ld hl, 6 : add hl, de

    ld c, (hl)
    inc hl 
    ld b, (hl)
.addr
    ld hl, 0
.loop
    ld a, (hl) : call Uart.write
    inc hl
    dec bc
    ld a, b : or c : jp nz, .loop
    ; A already zero here
    ret

TCPIP_UDP_RCV:
    publishByte OP_RECV_DATAGR
    ld a, b : call Uart.write
    ex de, hl
    call Uart.writeHL
    ex de,hl
    call Uart.readB : and a : ret nz
    ex de, hl
    call Uart.readBHL : ld (.ip1 + 1), hl
    call Uart.readBHL : ld (.ip2 + 1), hl
    call Uart.readBHL : ld (.port + 1), hl
    call Uart.readBHL : ld (.act + 1), hl
.loop
    call Uart.readB : ld (de), a
    inc de
    dec hl
    ld a, h : or l :jr nz, .loop
.ip1
    ld hl, 0
.ip2
    ld de, 0
.port
    ld ix, 0
.act
    ld bc, 0
    xor a 
    ret

; HL = parameter block:
;   +0 (4) remote IP, +4 (2) remote port, +6 (2) local port,
;   +8 (2) user timeout, +10 (1) flags (bit 0: passive, bit 1: resident, bit 2: TLS, bit 3: verify)
; The whole block is handed to the firmware, which validates it and opens
; the connection in active or passive (LISTEN) mode.
; Output: A = error, B = connection number, C = close reason (if A = ERR_NO_CONN)
TCPIP_TCP_OPEN:
    publishByte OP_OPEN_TCP_EX
    ld b, 11
.send
    ld a, (hl) : call Uart.write : inc hl
    djnz .send

    call Uart.readB : and a : jr z, .ok
    cp ERR_NO_CONN : ret nz          ; Any other error: nothing else follows
    call Uart.readB : ld c, a        ; Close reason
    ld a, ERR_NO_CONN
    ret
.ok
    call Uart.readB : ld b, a
    xor a
    ret

TCPIP_TCP_CLOSE:
    publishByte OP_CLOSE_TCP
    ld a, b : call Uart.write
    jp Uart.readB

TCPIP_TCP_ABORT:
    publishByte OP_ABORT_TCP
    ld a, b : call Uart.write
    jp Uart.readB

; Input: B = connection number, HL = info block address (0 = not needed)
; Output: A = error, B = state, C = flags / close reason,
;         HL = incoming bytes, DE = urgent bytes (0), IX = output buffer space (#FFFF)
TCPIP_TCP_STATE:
    publishByte OP_EXT_STATUS_TCP
    ld a, b : call Uart.write
    call Uart.readB : and a : jr z, .ok
    cp ERR_NO_CONN : jr nz, .err
    call Uart.readB : ld c, a        ; Close reason
    ld a, ERR_NO_CONN
.err
    ld b, 0
    ld hl, 0, de, 0, ix, #ffff
    ret
.ok
    ; 8 bytes of connection information: remote IP, remote port, local port
    ld a, h : or l : jr z, .skipInfo
    dup 8
    call Uart.readB : ld (hl), a : inc hl
    edup
    jr .state
.skipInfo
    dup 8
    call Uart.readB
    edup
.state
    call Uart.readB : ld b, a        ; Connection state
    call Uart.readB : ld c, a        ; Flags
    call Uart.readBHL                ; Available bytes
    ld ix, #ffff, de, 0
    xor a
    ret

TCPIP_TCP_SEND:
    ld a, h : or l : ret z
    publishByte OP_SEND_TCP
    ld a, b : call Uart.write
    call Uart.writeHL
    call Uart.readB : and a : ret nz
.loop
    ld a, (de) : call Uart.write
    inc de : dec hl
    ld a, h : or l : jr nz, .loop
    ret

TCPIP_TCP_RCV:
    publishByte OP_RECV_TCP
    ld a, b : call Uart.write
    call Uart.writeHL
    call Uart.readB : and a : ret nz
    call Uart.readBHL
    push hl
    ld a, h : or l : jr z, .exit
.loop
    call Uart.readB : ld (de), a : inc de
    dec hl
    ld a, h : or l : jr nz, .loop
.exit
    pop bc
    ld hl, 0
    xor a
    ret

;--- Compare HL and DE
;    Input:  HL, DE = values to compare
;    Output: Cy set if HL<DE
;            Z  set if H=DE
;    Modifies: AF
COMP16:
	ld	a,h
	sub	d
	ret	nz
	ld	a,l
	sub	e
	ret

;--- Convert a character to upper-case if it is a lower-case letter
TOUPPER:
	cp	"a"
	ret	c
	cp	"z"+1
	ret	nc
	and	#DF
	ret
    
    include "driver/uart.asm"

TIMEOUT_COUNTER			dw	0

;============================
;===  UNAPI related data  ===
;============================

; This data is setup at installation time

MY_SLOT:				db	0
MY_SEG:					db	0
;--- Specification identifier (up to 15 chars)

UNAPI_ID:				db	"TCP/IP",0
UNAPI_ID_END:

;--- Implementation name (up to 63 chars and zero terminated)

APIINFO:				ds 63

ROM_V_P					db	1
ROM_V_S					db	1

SEG_CODE_END:
; We will be in a segment of our own, running from 0x4000 to 0x7FFF
; Use this to check, if this is beyond #7FFF, code is too fat and won't fit
; 16K segment, so need to re-design it to fit into the segment
LAST_RAM_BYTE_USED		equ	SEG_CODE_END
    display "Code ends: ", $