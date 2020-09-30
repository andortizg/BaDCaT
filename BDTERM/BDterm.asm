/*
--
--   BaDCaT Terminal
--   Revision 1.10
--
-- Requires SJASM to compile
-- Copyright (c) 2020 Andres Ortiz (andres.ortizg1@gmail.com)
-- All rights reserved.
--
-- Redistribution and use of this source code or any derivative works, are
-- permitted provided that the following conditions are met:
--
-- 1. Redistributions of source code must retain the above copyright notice,
--    this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
-- 3. Redistributions may not be sold, nor may they be used in a commercial
--    product or activity without specific prior written permission.
-- 4. Source code of derivative works MUST be published to the public.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
-- "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
-- TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
-- CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
-- EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
-- PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
-- OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
-- OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
-- ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
*/
        output "BDterm.bin"

// Bios Routines
POSIT   equ     #00C6   ; H -> Y coordinate of cursor, L -> X coordinate of cursor
ERAFNK  equ     #00CC
DSPFNK  equ     #00CF
ENASLT  equ     #0024
slotvar equ     #8501   ; My Rom slot
RSLREG  equ     #0138
BREAKX	equ	#00B7   ; check Ctrl-STOP
DCOMPR  equ     #0020
// HOOKS
HTIMI   equ     #FD9F   ; VBLANK
HKEYI   equ     #FD9A   ; H.KEYI

// System Variables
GETPNT  equ     #F3FA
old_isr equ     #F200   ; 5 bytes for the old isr jump code
CSRX    equ     #F3DD   ; Current cursor X-position
CSRY    equ     #F3DC   ; Current cursor Y-position
JIFFY   equ     #FC9E   ; To count VBLANK interrupts
EXPTBL  equ     #FCC1   ; Bios Slot / Expansion Slot
CLIKSW  equ     #F3DB   ; Key click


// UART baseport
baseport equ #80

// Ring buffer version
// 256 bytes Ring buffer is implemented, so buffersize var is not really needed
buffersize  equ 256




    db  #fe
    dw  START
    dw  END
    dw  START
    org #C000                           ; Program in page 3


START:
        call     ERAFNK                 ; Delete function keys
        ld       b,160
        ld       ix,0xF87F              ; Delete F1 function key
.efnk   ld       (ix),0
        inc      ix
        djnz     .efnk

        ld      hl,TEXT_INIT
        call    print_var_len_text
        call    PUTCRLF

        ; Manage interrupts
        ; Save old isr at old_isr
        ld      hl,HKEYI
        ld      de,old_isr
        ld      bc,5
        ldir
        
        ; UART ISR install
        di
        ld      a,#c3
        ld      hl,UART_isr
        ld      [HKEYI],a
        ld      [HKEYI+1],hl

        ld      a,0             ; RTS=0 to avoid receiving bytes
        out     (baseport+4),a
        
        call    ERAFNK

        call    Init   
        call    flushbuf
        
        
        ld      A,#2             ; RTS=1 to receive & loopback
        out     (baseport+4),A



        jp      main_loop



;****************** UART_ISR definition ****************************
;*******************************************************************
UART_isr:
        push    hl
        push    af
        ; *** ISR routine starts HERE
        

        ; Check UART IIR register
        in      a,(baseport+2)
        and     1                       ; 11000100 (received Data interrupt, FIFO trigger)
        jr      nz,.eisr                ; Interrupt not from UART. exit
        ; Unset RTS
        ld      a,0
        out     (baseport+4),a

        ; UART interrupt, RX data available. 
        
        ; Fill the buffer until it is full or there is not more data
        ; Ring buffer is implemented. 

.flbuf: 

        ld      ix,RXBUFFER
        ld      a,(wptr)    
        ld      d,0
        ld      e,a                      
        add     ix,de

.fifor: 
        ; Buffer lleno?
        ld      a,(rptr)
        ld      b,a
        ld      a,(wptr)
        inc     a
        cp      b               ; write+1=read ?
        jr      z,.eisr         ; Buffer lleno. Se sale y se deja RTS=0 para evitar overrun
        ; Queda espacio en el buffer
        in      a,(baseport+5)          ; FIFO vacia?
        and     1               
        jr      z,.eisr                 ; FIFO Vacia. Sale de la ISR
        ; Quedan datos en la FIFO. Se rellena el buffer
        in      a,(baseport)            ; Se recibe el byte de la FIFO
        ld      (ix),a                  ; Se almacena en el buffer
        ; *** Inc write pointer and update buffer position. !!! #FF + 1 -> #00 !!!! (8-bits arithmetic)
        ld      a,(wptr)        ; 8 bit arithmetic to ensure overflow pointers!
        inc     a
        ld      (wptr),a
        ld      d,0
        ld      e,a
        ld      ix,RXBUFFER
        add     ix,de
        jr      .fifor     
.eisr: 
        pop     af
        pop     hl
        ;reti
        jp      old_isr     

;*************************************** UART Functions **************************
// UART INITIALIZATION
Init:
        di
        ; Unset RTS
        ; Enable FIFO
        ld	    a,0x07
	out	    (baseport+2),a	
	out	    (baseport+2),a
        ; Set Speed
        ld      a,0x80           ; Set-up access to baud divisor latch (DLAB FLAG)
        out     (baseport+3),a   ; writing 0x80 (bit 7 set) to the LCR (0x83) register
        ld      a,0x02           ; Program DLL (LOW BYTE)
        out     (baseport),a
        ld      a,0x00           ; Program DML (HIGH BYTE)
        out     (baseport+1),a   ; DLL=01, DLM=0 -> 57K6 bauds by default
        ; Set protocol
        ld      a,0x03           ; 8, N, 1 writting 0x03  00000011b
        out     (baseport+3),a   ; to  LCR (0x83) register. This RESET the DLAB FLAG
        ; Enable Interrupts
	ld	 a,1
	out	 (baseport+1),a	     ; enable Data Received interrupt
        ei
        ret 

// Return the number of unreaded bytes in A
; Z=1 if there are not unreaded bytes in buffer (rptr=wptr)
; wptr is always > rptr !
chars_in_buf:
        ld      a,(wptr)
        ld      b,a
        ld      a,(rptr)
        cp      b               ; 
        jr      c,.rlw          ; rptr<wptr?  -> wptr-rptr chars in buf
        jr      z,.rew          ; rptr=wptr   -> Buffer vacio
        ; wptr < rptr
        ld      a,#ff
        ld      hl,rptr
        sub     (hl)            ; a=#ff-rptr
        ld      hl,wptr
        add     a,(hl)          ; a=#ff-rptr+ wptr
        ret     
.rlw:   ld      a,(wptr)
        ld      hl,rptr
        sub     (hl)            ; a=wptr-rptr
        ret 
.rew:   ld      a,0
        ret     


// A=0 if buffer is empty
; A=1 if there are bytes to be read in the buffer 
rs_in_stat:
        ld      a,(wptr)
        ld      b,a
        ld      a,(rptr)
        cp      b               ; 
        jr      nz,.emp          ; rptr=wptr   -> Buffer vacio
        ld      a,1
        ret
.emp:   ld      a,0
        ret     

// Receive one byte from ring buffer
; A=Received byte. 
rs_in:
        ld      a,(wptr)
        ld      b,a
        ld      a,(rptr)
        cp      b
        jr      z,.erx          ; if wptr=rptr there are no bytes left. Exit
        ; a=rptr, b=bytes to recieve
        ld      d,0
        ld      a,(rptr)
        ld      e,a
        ld      ix,RXBUFFER
        add     ix,de
        inc     a
        ld      (rptr),a
        ld      a,(ix)
.erx    ret 

// RS232 De Init Routine
; This deactivates the interrupts from the UART
DeInit:
	di
	ld	a,00000111b
	out     (baseport+3),a
	ld	a,0
	out     (baseport+4),a
	ld	a,0
	out	(baseport+1),a	; disable interrupts
	ei
	ret

// Put a byte in the TX FIFO
; A=Byte to be sent
rs_out:
        ld      (AUX),a
.rsol:  IN      A,(baseport+5)          ; wait for TX ready
        AND     32
        JR      Z,.rsol                  ; 32= 100000 (THRE bit)   
        LD      A,(AUX)
        OUT     (baseport),A            ; Send keypressed to the TX FIFO
        ret 


// Flush RX buffer
flushbuf:
        xor     a
        ld      (rptr),a        ; Reset read pointer
        ld      (wptr),a        ; Reset write pointer
        ld      b,buffersize-1   
        ld      IX,RXBUFFER     ; Initial position
.fll:   ld      (IX),0          ; Fill with zeros
        inc     IX
        djnz    .fll
        ld      hl,wptr
        ld      hl,rptr
        ret     



;****************************************************************************************************
// A simple delay function
Simple_Delay:
        ld	    B,#FF
.dl:    nop
	djnz	    .dl
	ret    

;************************* NUMERIC CONVERSION ROUINES ******************************
; Input: HL -> Pointer to string number
; Output: HL -> Unsigned Integer number
;
Str2int:
        ld      (CW),hl
        ld      ix,(CW)
        ld      a,(ix)
        sub     a,48
        ld      de,10000
        call    Mult12                  ; Result in HL
        ld      de,(NUM)
        add     HL,de
        ld      (NUM),hl
        inc     ix
        
        ld      a,(ix)
        sub     a,48
        ld      de,1000
        call    Mult12                  ; Result in HL
        ld      de,(NUM)
        add     hl,de
        ld      (NUM),hl
        inc     ix

        ld      a,(ix)
        sub     a,48
        ld      de,100
        call    Mult12                  ; Result in HL
        ld      de,(NUM)
        add     hl,de
        ld      (NUM),hl
        inc     ix

        ld      a,(ix)
        sub     a,48
        ld      de,10
        call    Mult12                  ; Result in HL
        ld      de,(NUM)
        add     hl,de
        ld      (NUM),hl
        inc     ix

        ld      a,(ix)
        sub     a,48
        ld      de,(NUM)
        ld      h,0
        ld      l,A
        add     hl,de
        ret     


;Number to ASCII conversion Routine. From http://map.grauw.nl/sources/external/z80bits.html
;Input: HL = number to convert, DE = location of ASCII string
;Output: ASCII string at (DE)

Num2Dec	
        ld	bc,-10000
	call	Num11
	ld	bc,-1000
	call	Num11
	ld	bc,-100
	call	Num11
	ld	c,-10
	call	Num11
	ld	c,b

Num11	ld	a,'0'-1
Num12	inc	a
	add	hl,bc
	jr	c,Num12
	sbc	hl,bc
	ld	(de),a
	inc	de
	ld      a,"$"
        ld      (de),a
        ret

; Number to ASCII (HEX) conversion Routine. From http://map.grauw.nl/sources/external/z80bits.html
; Input: HL = number to convert, DE = location of ASCII string
; Output: ASCII string at (DE)

Num2Hex:
	ld	a,h
	call	Num21
	ld	a,h
	call	Num22
	ld	a,l
	call	Num21
	ld	a,l
	jr	Num22

Num21:	rra
	rra
	rra
	rra
Num22:	or	#F0
	daa
	add	a,#A0
	adc	a,#40
	ld	(de),a
	inc	de
        ld      a,"$"
        ld      (de),a
	ret

; Multiply 8-bit value with a 16-bit value. From http://map.grauw.nl/sources/external/z80bits.html
; In: Multiply A with DE
; Out: HL = result
;
Mult12:
    ld l,0
    ld b,8
Mult12_Loop:
    add hl,hl
    add a,a
    jr nc,Mult12_NoAdd
    add hl,de
Mult12_NoAdd:
    djnz Mult12_Loop
    ret
;*******************************************************************************
;*************************** MAIN PROGRAM STARTS HERE **************************
;*******************************************************************************
main_loop:
        call    BREAKX
        jr      nc,.ctx
        call    DeInit
        ret     

.ctx    
        call    check_F1
        and     A
        jp      nz,LOADBIN
        ;CALL    check_F3
        ;AND     A
        ;JR      Z,.ink
        ;LD      A,(LECHO)
        ;XOR     #FF
        ;LD      (LECHO),A

.ink:   call    INKEY
        jr      z,RXloop

TXready:
        in      a,(baseport+5)          ; wait for TX ready
        and     32
        jr      z,TXready
        
        ld      a,(KEYPRESSED)
        cp      8
        jr      z,backspace
        cp      13
        jr      z,line_end
        ld      a,(KEYPRESSED)
        call    rs_out  
        ld      a,(LECHO)
        and     #FF
        jr      z,main_loop
        ld      a,(KEYPRESSED)
        call    CHPUT
        jr      main_loop

backspace:
        ld      a,(CSRX)
        cp      1
        jr      z,main_loop
        ld      a,8
        call    CHPUT
        ld      a," "
        call    CHPUT
        ;LD      a,8                    ; Needed for Local ECHO 
        ;CALL    CHPUT          
        ld      a,(KEYPRESSED)
        call    rs_out
        jr      main_loop

line_end:
        ld      a,13
        call    CHPUT
        ld      a,13
        call    rs_out
        ld      a,10
        call    CHPUT
        jr      main_loop 

RXloop:
        call    chars_in_buf
        ld      (cib),a
        jr      z,.erl            ; Chars in buf = 0? -> Assert RTS and loop
        call    rs_in
        ld      (AUX),a
        cp      10
        jr      nz,.nclf
        ld      a,13
        call    CHPUT
        ld      a,10
        call    CHPUT
        jr      .cnt
.nclf:  call    CHPUT
.cnt:   ld      b,20
        ld      a,(cib)
        cp      b                 ; (cib)<20? -> Keep RTS OFF
        jr      nc,.ere
.erl:   
        ld      a,#2
        out     (baseport+4),a        ; RTS=1
        
.ere:   jp      main_loop

// Write CR+LF to Screen
PUTCRLF:

        ld      a,13
        call    CHPUT
        ld      a,10
        call    CHPUT
        ret     

;******************** Checks whether Function key was pressed *********************
; Output: A=1 if F1 Pressed
check_F1: 
        in      a,(#AA)
        and     #F0          ; only change bits 0-3
        ld      b,6
        or      b            ; take row number from B
        out     (#AA),a
        in      a,(#A9)      ; read row into A
        cp      11011111b
        jr      z,.rt
        xor     a
        ret
.rt:    ld      a,1
        ret

; Output: A=1 if F5 Pressed
check_F3: 
        in      a,(#AA)
        and     #F0          ; only change bits 0-3
        ld      b,6
        or      b            ; take row number from B
        out     (#AA),a
        in      a,(#A9)      ; read row into A
        cp      01111111b
        jr      z,.rt
        xor     a
        ret
.rt:    ld      a,1
        ret
;***********************************************************************************

;***********************************************************************************
;********************* LOAD BINARY FILES INTO MEMORY *******************************
;***********************************************************************************
LOADBIN:
        ld      hl,DOWNLOAD_TEXT
        call    print_var_len_text
        call    flushbuf
        ; Request file size (command <)
        ld      a,'<'
        call    rs_out
        ld      hl,JIFFY
        ld      de,250
        add     hl,de
        ld      (TIMER),hl
.wb:    call    chars_in_buf            ; Wait for BaDCaT's response
        cp      5
        jr      z,.strx
        ld      hl,JIFFY
        ld      de,(TIMER)
        call    DCOMPR
        jr      c,.wb
        ld      hl,TIMEOUT_TXT
        call    print_var_len_text
        call    flushbuf
        jp      main_loop

        

        ; Receive the file length
.strx:  ld      hl,STRNUM
        ld      b,5
.rxsl:  push    bc
        call    rs_in
        pop     bc
        ld      (hl),a
        inc     hl
        djnz    .rxsl        
        ; Convert string into number and store in HL
        ld      hl,STRNUM
        call    Str2int
        ld      (BYTES2RX),hl   ; Save in BYTES2RX
        ld      hl,RCV_TEXT
        call    print_var_len_text
        ld      hl,STRNUM
        call    print_var_len_text
        ld      hl,BYTES_TEXT
        call    print_var_len_text
        ld      a,13
        call    CHPUT
        ld      a,10
        call    CHPUT


;*************************************************************************
; *** This routine selects the same slot in page 1 that you have in page 3, 
; *** which will always be the system RAM
; *** From http://map.tni.nl/sources/raminpage1.php
;*************************************************************************

Enable_RAM2: ld     a,(EXPTBL+3)
             ld     b,a                 ;check if slot is expanded
             and    a
             jp     z,Ena_RAM2_jp
             ld     a,(#FFFF)           ;if so, read subslot value first
             cpl                        ;complement value
             and    %11000000
             rrca                       ;shift subslot bits to bits 2-3
             rrca
             rrca
             rrca
             or     b
             ld     b,a
Ena_RAM2_jp: in     a,(#A8)             ;read slot value
             and    %11000000           ;shift slot bits to bits 0-1
             rlca
             rlca
             or     b
             ld     h,#40               ;select slot
             call   ENASLT
;***************************************************************************
        
        
        ; Start TX
        ld      a,'>'
        call    rs_out
        ld      a,'+'
        call    rs_out
        
        ld      hl,(BYTES2RX)
        ld      a,#40
        cp      h               ; BYTES2RX>#40000 (16KB) ?
        jr      c, c32K
        jr      c16K

c16K:
        ; Copy to Page 1  
        ld      hl,(BYTES2RX)   ; Bytes to copy
        ld      de,#4000        ; Starting at #4000 
        call    RX2MEM
        jp      ROMexec
c32K:
        ; Copy to Pages 1 and 2 - 'AB' signature is found in Page 1
        ld      hl,(BYTES2RX)   ; Bytes to copy
        ld      de,#4000        ; Starting at #4000 
        call    RX2MEM
        ld      ix,#4000
        ld      h,(ix+3)
        ld      l,(ix+2)
        jp      hl
        ; Binary copied into RAM. Now, execute it

ROMexec:  
        ; Retrieve the execution address and jump
        ld      ix,#4000
        ld      h,(ix+3)
        ld      l,(ix+2)
        jp      hl


        
;************************************************************************
; ****** Store bytes received from UART into RAM ****** *****************
; Input: DE-> Initial RAM address, HL -> Number of bytes to store 
; Execute with JP !
;************************************************************************
RX2MEM:
        ld      a,0
        out     (baseport+1),a  ; Disable UART interrupts to speed up the proccess
        ; Receive bytes and store in RAM, initial address DE
        ld      (AUX),de
        ld      ix,(AUX)
        ; Loop to receive HL bytes
.lbl:   in      A,(baseport+5)  ; Check Data Ready bit
        and     00000001b               
        jr      NZ,.Mrxfifo     ; DR=1 -> receive the FIFO
.lblc:  ld      A,2             ; DR=0 -> Re-assert RTS
        out     (baseport+4),a
        jr      .lbl
        ; Loop to copy FIFO bytes into RAM
.Mrxfifo:
        in      a,(baseport+5) ; Check LSR - Data Ready
        and     00000001b
        jr      z,.lblc        ; Data not ready, re-assert RTS
        in      a,(baseport)   ; Receive a byte in A
        ld      (ix),a         ; and Load into (IX)

        inc     ix             ; Increment IX the pointer
        ;LD      HL,(BYTES2RX)
        dec     hl             ; Decrement BYTES2RX
        ;LD      (BYTES2RX),HL
        ld      a,h
        and     a
        jr      z,.cL
        jr      .Mrxfifo
.cL     ld      a,l
        and     a
        ret     z
        ;JR      Z,.lble
        jr      .Mrxfifo
;*******************************************************************************



;************************************************
; Print variable length text until "$" is found
; HL -> address of the variable size buffer
; Modifies HL, AF, B
;************************************************
print_var_len_text:
        ld      a,(hl)
        cp      '$'
        ret     z
        call    CHPUT
        inc     hl
        jr      print_var_len_text
;********************************************

;*********************************
;
;   List 5.5	get key code
;
;		this routine doesn't wait for key hit
;
; A -> ASCII CODE OF THE PRESSED KEY
; C -> 0 IF A KEY WAS PRESSED 
;********************************************************
;
CHSNS	EQU	009CH		;check keyboard buffer
CHGET	EQU	009FH		;get a character from buffer
CHPUT	EQU	00A2H		;put a character to screen
KILBUF	EQU	0156H		;clear keyboard buffer
REPCNT	EQU	0F3F7H		;time interval until key-repeat
KEYBUF	EQU	0FBF0H		;keyboard buffer address


; Real-time input using CHGET

INKEY:
        call	CHSNS		;check keyboard buffer
        jr      z,KEY1
	ld	a,8
	ld	(REPCNT),a	;not to wait until repeat
	call	CHGET		;get a character (if exists)
	jr	KEY2

KEY1:	
        ;LD	A,0x00      ;A := '-'
        ret
KEY2:	
        ;CALL	CHPUT		;put the character
	ld      (KEYPRESSED),a
        call	KILBUF		;clear keyboard buffer
	;CALL	BREAKX		;check Ctrl-STOP
	;JR     NC,INKEY
        ;LD     A,(KEYPRESSED)
        ret



KEYPRESSED:             DB  0
TXBUFFER:               DB  40,0xFF
TXBUFP:                 DB  0
STRNUM                  DS  6,"$"
TEXT_INIT               DB "BaDCaT Terminal v1.1 by Andres Ortiz",13,10,"$"
TEXT_INIT_UART          DB "16550 UART INITILIZATION",13,10,"$"
RCV_TEXT                DB "LOADING: ","$"
DOWNLOAD_TEXT           DB "LOADING ","$"
BYTES_TEXT              DB " BYTES","$"
LOAD_TXT                DB "LOADING STARTED",13,10,"$"
TIMEOUT_TXT             DB "BaDCaT did not respond!",13,10,"$"
RTS                     DB  0   ; RTS Signal copy
LECHO                   DB  0  ; Local Echo
BYTES2RX                DB  0
CW                      DW  0
NUM                     DW  0
AUX                     DB  0
RXBUFFER                DS  buffersize,0    ; Ring buffer (with 8 bit pointers)
rptr                    DB  0               ; Write pointer for ring bufferptr. Pointer will reset when overflowed
wptr                    DB  0               ; Read pointer for ring buffer
cib                     DB  0
TIMER                   DW  0


; Speedtable for 1,8432 MHz
speedtable1:
	dw	384		;1 300
	dw	192		;2 600
	dw	96		;3 1200
	dw	48		;4 2400 (with a little error)
	dw	24		;5 4800 (idem)
	dw	12		;6 9600 "
	dw	6		;7 19200
	dw	3		;8 38400
	dw	2		;9 57600
	dw	1		;A 115200

; Speedtable for 18,432 MHz
speedtable2:
	 dw	 15360		 ;0 75
	 dw	 3840		 ;1 300
	 dw	 1920		 ;2 600
	 dw	 960		 ;3 1200
	 dw	 480		 ;4 2400 (with a little error)
	 dw	 240		 ;5 4800 (idem)
	 dw	 120		 ;6 9600 "
	 dw	 60		 ;7 19200
	 dw	 30		 ;8 38400
	 dw	 20		 ;9 57600
	 dw	 10		 ;A 115200.

END:
