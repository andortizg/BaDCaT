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

    output "nifi.com"
	
;--- Just dumb driver that's do nothing

;*******************
;***  CONSTANTS  ***
;*******************

;--- System variables and routines

_TERM0:					equ	#00
_STROUT:				equ	#09
MODEM_RETRIES:			equ	60		; reset attempts before giving up (about 10 s)
ENASLT:					equ	#0024
EXTBIO:					equ	#FFCA
ARG:					equ	#F847
H_TIMI:					equ	#FD9F

;--- API version and implementation version
API_V_P:				equ	1
API_V_S:				equ	1

;--- Maximum number of available standard and implementation-specific function numbers
;Must be 0 to 127
MAX_FN:					equ	29

;Must be either zero (if no implementation-specific functions available), or 128 to 254
MAX_IMPFN:				equ	0

;--- TCP/IP UNAPI error codes

ERR_OK:					equ	0
ERR_NOT_IMP:			equ	1
ERR_NO_NETWORK:			equ	2
ERR_NO_DATA:			equ	3
ERR_INV_PARAM:			equ	4
ERR_QUERY_EXISTS:		equ	5
ERR_INV_IP:				equ	6
ERR_NO_DNS:				equ	7
ERR_DNS:				equ	8
ERR_NO_FREE_CONN:		equ	9
ERR_CONN_EXISTS:		equ	10
ERR_NO_CONN:			equ	11
ERR_CONN_STATE:			equ	12
ERR_BUFFER:				equ	13
ERR_LARGE_DGRAM:		equ	14
ERR_INV_OPER:			equ	15

;--- TCP/IP UNAPI connection Status
UNAPI_TCPIP_NS_CLOSED	equ	0
UNAPI_TCPIP_NS_OPENING	equ	1
UNAPI_TCPIP_NS_OPEN		equ	2
UNAPI_TCPIP_NS_UNKNOWN	equ	255


;***************************
;***  INSTALLATION CODE  ***
;***************************

	org	#100

	;--- Show welcome message

	ld	de,WELCOME_S
	ld	c,_STROUT
	call	5

	;--- Locate the RAM helper, terminate with error if not installed

	ld	de,#2222
	ld	hl,0
	ld	a,#FF
	call	EXTBIO
	ld	a,h
	or	l
	jr	nz,HELPER_OK

	ld	de,NOHELPER_S
	ld	c,_STROUT
	call	5
	ld	c,_TERM0
	jp	5
HELPER_OK:
	ld	(HELPER_ADD),hl
	ld	(MAPTAB_ADD),bc

	;--- Check if we are already installed.
	;    Do this by searching all the TCP/IP
	;    implementations installed, and comparing
	;    the implementation name of each one with
	;    our implementation name.

	;* Copy the implementation identifier to ARG

	ld	hl,UNAPI_ID-SEG_CODE_START+SEG_CODE
	ld	de,ARG
	ld	bc,UNAPI_ID_END-UNAPI_ID
	ldir

	;* Obtain the number of installed implementations

	ld	de,#2222
	xor	a
	ld	b,0
	call	EXTBIO
	ld	a,b
	or	a
	jr	z,NOT_INST

	;>>> The loop for each installed implementations
	;    starts here, with A=implementation index

IMPL_LOOP:	push	af

	;* Obtain the slot, segment and entry point
	;  for the implementation

	ld	de,#2222
	call	EXTBIO
	ld	(ALLOC_SLOT),a
	ld	a,b
	ld	(ALLOC_SEG),a
	ld	(IMPLEM_ENTRY),hl

	;* If the implementation is in page 3
	;  or in ROM, skip it

	ld	a,h
	and	%10000000
	jr	nz,NEXT_IMP
	ld	a,b
	cp	#FF
	jr	z,NEXT_IMP

	;* Call the routine for obtaining
	;  the implementation information

	ld	a,(ALLOC_SLOT)
	ld	iyh,a
	ld	a,(ALLOC_SEG)
	ld	iyl,a
	ld	ix,(IMPLEM_ENTRY)
	ld	hl,(HELPER_ADD)
	xor	a
	call	CALL_HL	;Returns HL=name address

	;* Compare the name of the implementation
	;  against our own name

	ld	a,(ALLOC_SEG)
	ld	b,a
	ld	de,APIINFO-SEG_CODE_START+SEG_CODE
	ld	ix,(HELPER_ADD)
	inc	ix
	inc	ix
	inc	ix	;Now IX=helper routine to read from segment
NAME_LOOP:	ld	a,(ALLOC_SLOT)
	push	bc
	push	de
	push	hl
	push	ix
	call	CALL_IX
	pop	ix
	pop	hl
	pop	de
	pop	bc
	ld	c,a
	ld	a,(de)
	cp	c
	jr	nz,NEXT_IMP
	or	a
	inc	hl
	inc	de
	jr	nz,NAME_LOOP

	;* The names match: already installed

	ld	de,ALINST_S
	ld	c,_STROUT
	call	5
	ld	c,_TERM0
	jp	5

	;* Names don't match: go to the next implementation

NEXT_IMP:	pop	af
	dec	a
	jr	nz,IMPL_LOOP

	;* No more implementations:
	;  continue installation process

NOT_INST:
	;--- Obtain the mapper support routines table, if available
	xor	a
	ld	de,#0402
	call	EXTBIO
	or	a
	jr	nz,ALLOC_DOS2

	;--- DOS 1: Use the last segment on the primary mapper
	ld	a,2
	ld	(MAPTAB_ENTRY_SIZE),a

	ld	hl,(MAPTAB_ADD)
	ld	b,(hl)
	inc	hl
	ld	a,(hl)
	jr	ALLOC_OK

	;--- DOS 2: Allocate a segment using mapper support routines

ALLOC_DOS2:
	ld	a,b
	ld	(PRIM_SLOT),a
	ld	de,ALL_SEG
	ld	bc,15*3
	ldir

	ld	de,0401h
	call	EXTBIO
	ld	(MAPTAB_ADD),hl

	ld	a,8
	ld	(MAPTAB_ENTRY_SIZE),a

	ld	a,(PRIM_SLOT)
	or	%00100000					;Try primary mapper, then try others
	ld	b,a
	ld	a,1		;System segment
	call	ALL_SEG
	jr	nc,ALLOC_OK

	ld	de,NOFREE_S					;Terminate if no free segments available
	ld	c,_STROUT
	call	5
	ld	c,_TERM0
	jp	5

ALLOC_OK:
	ld	(ALLOC_SEG),a
	ld	a,b
	ld	(ALLOC_SLOT),a

	;--- Switch segment, copy code, and setup data

	call	GET_P1					;Backup current segment
	ld	(P1_SEG),a

	ld	a,(ALLOC_SLOT)				;Switch slot and segment
	ld	h,#40
	call	ENASLT
	ld	a,(ALLOC_SEG)
	call	PUT_P1

	ld	hl,#4000					;Clear the segment first
	ld	de,#4001
	ld	bc,#4000-1
	ld	(hl),0
	ldir

	ld	hl,SEG_CODE					;Copy the code to the segment
	ld	de,#4000
	ld	bc,SEG_CODE_END-SEG_CODE_START
	ldir

	ld	hl,(ALLOC_SLOT)				;Setup slot and segment information
	ld	(MY_SLOT),hl

	;* Now backup and patch the EXTBIO and H_TIMI hooks

	di
	ld	hl,EXTBIO
	ld	de,OLD_EXTBIO
	ld	bc,5
	ldir

	ld	hl,H_TIMI
	ld	de,OLD_HTIM_I
	ld	bc,5
	ldir

	; First the EXTBIO Hook at index 6 / 4012
	ld	a,6							;Index 6 or 4012
	ld	ix,EXTBIO					;EXTBIO hook
	call	PATCH_HOOK

	xor	a							; Index 0 or 4000
	ld	ix,H_TIMI					; VDP Interrupt Hook
	call	PATCH_HOOK
	ei

;; Here we can init modem
    call Uart.init
    cp Uart.TYPE_NONE : jp z, NO_UART
    cp Uart.TYPE_16C550C : jr z, .afe
    ld de, SOFT_FLOW_S
    ld c, _STROUT
    call 5
.afe
    ld c, MODEM_RETRIES
.loop
    dec c : jp z, NO_MODEM
    ld a, OP_Reset : call Uart.write
    call Uart.readTimeout : jr nc, .loop
.byteAvail
    and a : jr nz, .flush ; Check to success staus
    call Uart.readTimeout : jr nc, .loop : cp 'N' : jr nz, .flush
    call Uart.readTimeout : jr nc, .loop : cp 'i' : jr nz, .flush
    call Uart.readTimeout : jr nc, .loop : cp 'F' : jr nz, .flush
    call Uart.readTimeout : jr nc, .loop : cp 'i' : jr nz, .flush
    call Uart.readTimeout : jr nc, .loop : and a  : jr nz, .flush
    jr .found
.flush
    ; Unexpected byte: drop whatever is pending and try again
    call Uart.readTimeout : jr c, .flush
    jr .loop
.found

    ld hl, APIINFO
    ld a, OP_VERSION_STR : call Uart.write
    call Uart.readB ; Ignore it :-) There nothing to fail
.loop2
    call Uart.readB 
    ld (hl), a
    inc hl
    and a : jr nz, .loop2


LOAD_RESTORE_SS:
	;--- Restore slot and segment, and terminate

	ld	a,(PRIM_SLOT)
	ld	h,#40
	call	ENASLT
	ld	a,(P1_SEG)
	call	PUT_P1

	ld	de,OK_S
	ld	c,_STROUT
	call	5
LOAD_EXIT:
	ld	c,_TERM0
	jp	5

; The UART or the modem does not answer: unhook, restore the segment and exit
NO_UART:
	ld	de,NO_UART_S
	jr	UNHOOK
NO_MODEM:
	ld	de,NO_MODEM_S
UNHOOK:
	push	de
	di
	ld	hl,OLD_EXTBIO
	ld	de,EXTBIO
	ld	bc,5
	ldir
	ld	hl,OLD_HTIM_I
	ld	de,H_TIMI
	ld	bc,5
	ldir
	ei
	ld	a,(PRIM_SLOT)
	ld	h,#40
	call	ENASLT
	ld	a,(P1_SEG)
	call	PUT_P1
	pop	de
	ld	c,_STROUT
	call	5
	jr	LOAD_EXIT

	;>>> Other auxiliary code
CALL_IX:	jp	(ix)
CALL_HL:	jp	(hl)

;--- This routine patches a hook so that
;    it calls the routine with the specified index
;    in the allocated segment.
;    Input: A  = Routine index, 0 to 63
;           IX = Hook address
;           ALLOC_SEG and ALLOC_SLOT set
PATCH_HOOK:
	push	af
	ld	a,0CDh						;Code for "CALL"
	ld	(ix),a
	ld	hl,(HELPER_ADD)
	ld	bc,6
	add	hl,bc						;Now HL points to segment call routine
	ld	(ix+1),l
	ld	(ix+2),h

	ld	hl,(MAPTAB_ADD)
	ld	a,(ALLOC_SLOT)
	ld	bc,(MAPTAB_ENTRY_SIZE)
	ld	b,0
	ld	d,a
	ld	e,0							;Index on mappers table
SRCHMAP:
	ld	a,(hl)
	cp	d
	jr	z,MAPFND
	add	hl,bc						;Next table entry
	inc	e
	jr	SRCHMAP
MAPFND:
	ld	a,e							;A = Index of slot on mappers table
	rrca
	rrca
	and	11000000b
	pop	de							;Retrieve routine index
	or	d
	ld	(ix+3),a

	ld	a,(ALLOC_SEG)
	ld	(ix+4),a
	ret


;****************************************************
;***  DATA AND STRINGS FOR THE INSTALLATION CODE  ***
;****************************************************

;--- Variables
PRIM_SLOT:				db	0		;Primary mapper slot number
P1_SEG:					db	0		;Segment number for TPA on page 1
ALLOC_SLOT:				db	0		;Slot for the allocated segment
ALLOC_SEG:				db	0		;Allocated segment
HELPER_ADD:				dw	0		;Address of the RAM helper jump table
MAPTAB_ADD:				dw	0		;Address of the RAM helper mappers table
MAPTAB_ENTRY_SIZE:		db	0		;Size of an entry in the mappers table:
									;- 8 in DOS 2 (mappers table provided by standard mapper support routines),
									;- 2 in DOS 1 (mappers table provided by the RAM helper)
IMPLEM_ENTRY:			dw	0		;Entry point for implementations
TEMP_RET:				db	0		;Store return values from the mapper page

;--- DOS 2 mapper support routines
ALL_SEG:				ds	3
FRE_SEG:				ds	3
RD_SEG:					ds	3
WR_SEG:					ds	3
CAL_SEG:				ds	3
CALLS:					ds	3
PUT_PH:					ds	3
GET_PH:					ds	3
PUT_P0:					ds	3
GET_P0:					ds	3
PUT_P1:
	out	(#FD),a
	ret
GET_P1:
	in	a,(#FD)
	ret
PUT_P2:					ds	3
GET_P2:					ds	3
PUT_P3:					ds	3

;--- Strings
WELCOME_S:
	db	"NiFi TCP/IP UNAPI Driver v1.1",13,10
	db	"(c)2021 Nihirash (c)2026 Andres Ortiz",13,10
	db	"Based on ducasp's UNAPI driver (c)2020",13,10
	db	"Active and passive TCP, UDP (firmware 0.2+)",13,10
	db	10
	db	"$"

NOHELPER_S:
	db	"*** ERROR: No UNAPI RAM helper is installed",13,10,"$"

NOMAPPER_S:
	db	"*** ERROR: No mapped RAM found",13,10,"$"

NOFREE_S:
	db	"*** ERROR: Could not allocate any RAM segment",13,10,"$"

OK_S:
	db	"Installed successfully.",13,10
	db	13,10,"$"
SOFT_FLOW_S:
	db	"UART without automatic flow control (16C550): using software flow control.",13,10,"$"
NO_UART_S:
	db	"ERROR: no 16C550 UART found at port #80. Driver not installed.",13,10,"$"
NO_MODEM_S:
	db	"ERROR: the modem does not answer. Driver not installed.",13,10,"$"

ALINST_S:
	db	"*** Already installed.",13,10,"$"
    include "driver/tcp.asm"