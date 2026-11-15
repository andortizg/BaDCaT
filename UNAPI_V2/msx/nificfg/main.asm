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

; NIFICFG - friendly WiFi configuration utility for the NiFi modem (MSX-DOS)
;
;   NIFICFG            interactive menu
;   NIFICFG /S         show network status and exit
;   NIFICFG /L         scan and list the access points and exit
;   NIFICFG /C ssid [password]
;                      connect to a network and exit (for AUTOEXEC.BAT)
;   NIFICFG /F         forget the stored network and disconnect
;   NIFICFG /U         update the modem firmware from the configured repository
;   NIFICFG /B [file]  update the modem firmware from a file on disk (NIFI.BIN)
;   NIFICFG /?         help
;
; SSIDs or passwords with spaces go between double quotes.
; Build: sjasmplus main.asm

    output "nificfg.com"
    org #100
    jp start
    include "driver/uart.asm"
    include "driver/nifi.asm"
    include "driver/console.asm"
    include "driver/dos.asm"

BDOS   = 5
_TERM0 = 0

MAX_LIST_SHOWN = 30
URL_MAX = 200
CFG_MAX = 1023
SSID_MAX = 32
PASS_MAX = 63

start:
    Print banner
    call parseArgs
    ld a, (mode)
    cp '?' : jp z, showHelp
    cp 'H' : jp z, showHelp

    call Uart.detect
    cp Uart.TYPE_NONE : jp z, noUart
    cp Uart.TYPE_16C550C : jr z, .uartOk
    Print uartWarning
.uartOk
    Print initMsg
    call Nifi.init : jp nz, noModem
    Print doneMsg

    ld a, (mode)
    cp 'S' : jp z, cmdStatus
    cp 'L' : jp z, cmdList
    cp 'F' : jp z, cmdForget
    cp 'C' : jp z, cmdConnect
    cp 'U' : jp z, cmdUpdate
    cp 'B' : jp z, cmdUpdateFile
    and a  : jp nz, badOption

;=====================================================================
; Interactive menu
;=====================================================================
menu:
    call Console.newLine
    call showHeader
    Print menuText
.key
    call Console.getKey
    cp '1' : jp z, mStatus
    cp '2' : jp z, mScan
    cp '3' : jp z, mManual
    cp '4' : jp z, mForget
    cp '5' : jp z, mInfo
    cp '6' : jp z, mUpdate
    cp '7' : jp z, mUpdateFile
    cp '0' : jp z, exit
    cp Console.KEY_ESC : jp z, exit
    jr .key

mStatus:
    call Console.newLine
    call showStatus
    jr pause
mScan:
    call Console.newLine
    call scanAndConnect
    jr pause
mManual:
    call Console.newLine
    call manualConnect
    jr pause
mForget:
    call Console.newLine
    call forgetNetwork
    jr pause
mInfo:
    call Console.newLine
    call showInfo
    jr pause
mUpdate:
    call Console.newLine
    call updateFirmware
    jr pause
mUpdateFile:
    call Console.newLine
    call updateFromFile
pause:
    Print pressKey
    call Console.getKey
    jp menu

;=====================================================================
; Command line modes
;=====================================================================
cmdStatus:
    call Console.newLine
    call showStatus
    jp exit

cmdList:
    call Console.newLine
    call scanList
    jp exit

cmdForget:
    call Console.newLine
    call Nifi.forgetAp
    and a : jr z, .ok
    call showError
    jp exit
.ok
    Print forgotten
    jp exit

cmdUpdate:
    call Console.newLine
    call updateFirmware
    jp exit

cmdUpdateFile:
    call Console.newLine
    ld hl, (argSsid)                 ; first argument = file name
    ld a, h : or l : jr z, .default
    ld de, fileName : call strCopy
    jr .go
.default
    ld hl, defBinName, de, fileName : call strCopy
.go
    call updateFromFile.named
    jp exit

cmdConnect:
    call Console.newLine
    ld hl, (argSsid)
    ld a, h : or l : jr z, .noSsid
    ld de, (argPass)
    call connectTo
    jp exit
.noSsid
    Print missingSsid
    jp showHelp

badOption:
    Print badOptionMsg
    jp showHelp

showHelp:
    Print helpText
    jp exit

noUart:
    Print noUartMsg
    jp exit
noModem:
    Print noModemMsg
exit:
    ld c, _TERM0
    jp BDOS

;=====================================================================
; Screens
;=====================================================================

; One line summary used on top of the menu
showHeader:
    Print hdrNetwork
    ld hl, buff : call Nifi.getAp
    and a : jr nz, .notConnected
    call putQuoted
    Print hdrIp
    ld a, Nifi.IP_LOCAL : call Nifi.getIp
    and a : jr nz, .nl
    ld (ipBuf), hl, (ipBuf + 2), de
    ld hl, ipBuf : call Console.dispIP
    Print hdrSignal
    call Nifi.getRssi : and a : jr nz, .nl
    ld a, c : call Console.dispBars
.nl
    jp Console.newLine
.notConnected
    Print notConnected
    jp Console.newLine

; Full status screen
showStatus:
    Print stFirmware
    ld hl, buff : call Nifi.getVer
    and a : jr nz, .noVer
    Print buff
    jr .ver2
.noVer
    Print naMsg
.ver2
    call Console.newLine

    Print stMac
    ld hl, macBuf : call Nifi.getMac
    and a : jr nz, .noMac
    ld hl, macBuf : call dispMac
    jr .mac2
.noMac
    Print naMsg
.mac2
    call Console.newLine

    Print stLink
    call Nifi.getNetState
    call dispNetState
    call Console.newLine

    Print stNetwork
    ld hl, buff : call Nifi.getAp
    and a : jr nz, .notConnected
    call putQuoted
    call Console.newLine

    Print stSignal
    call Nifi.getRssi : and a : jr nz, .noRssi
    ld a, c : call Console.dispSigned
    Print dbmMsg
    ld a, c : call Console.dispBars
    jr .sig2
.noRssi
    Print naMsg
.sig2
    call Console.newLine

    ld hl, ipLabels
    ld b, 5
.ipLoop
    push bc, hl
    ld e, (hl) : inc hl : ld d, (hl) : inc hl
    ld a, (hl)
    push af
    ex de, hl : call Console.putStringZ
    pop af
    call Nifi.getIp
    and a : jr nz, .ipErr
    ld (ipBuf), hl, (ipBuf + 2), de
    ld hl, ipBuf : call Console.dispIP
    jr .ipNext
.ipErr
    Print naMsg
.ipNext
    call Console.newLine
    pop hl, bc
    inc hl : inc hl : inc hl
    djnz .ipLoop
    ret
.notConnected
    Print notConnected
    call Console.newLine
    Print hintConnect
    jp Console.newLine

showInfo:
    Print infoText
    Print stFirmware
    ld hl, buff : call Nifi.getVer
    and a : jr nz, .noVer
    Print buff
    jr .ver2
.noVer
    Print naMsg
.ver2
    call Console.newLine
    Print stMac
    ld hl, macBuf : call Nifi.getMac
    and a : jr nz, .noMac
    ld hl, macBuf : call dispMac
    jr .mac2
.noMac
    Print naMsg
.mac2
    call Console.newLine
    Print stUart
    ld a, (Uart.type)
    call dispUartType
    Print stUartPort
    ld a, Uart.UART_BASE : call Console.dispHex
    jp Console.newLine

;=====================================================================
; Scan / connect
;=====================================================================

; Scans and prints the numbered list. A <- number of networks shown
; (also stored in apCount), C flag on error.
scanList:
    Print scanning
    ld hl, apList : call Nifi.getApList
    and a : jr z, .ok
    call showError
    scf
    ret
.ok
    Print listHeader
    ld hl, apList
    ld b, 0
.list
    ld a, (hl) : cp #ff : jr z, .listEnd
    ld a, b : cp MAX_LIST_SHOWN : jr z, .listEnd
    inc b
    ld a, b : call Console.dispA2
    ld a, 2 : call Console.spaces
    push hl
    call strEnd
    inc hl : ld a, (hl)              ; RSSI
    call Console.dispBars
    ld a, 2 : call Console.spaces
    inc hl : ld a, (hl)              ; encryption
    call dispEnc
    inc hl                           ; next entry
    ex (sp), hl                      ; HL = SSID, (SP) = next entry
    call Console.putStringZ
    call Console.newLine
    pop hl
    jr .list
.listEnd
    ld a, b
    ld (apCount), a
    and a : jr nz, .done
    Print noNetworks
.done
    and a
    ret

scanAndConnect:
    call scanList
    ret c
    and a : ret z
    Print selectPrompt
    ld hl, inBuf : ld b, 3 : call Console.readString
    call Console.newLine
    ld hl, inBuf + 2 : call Console.parseDec
    jr c, .cancel
    and a : jr z, .cancel
    ld c, a
    ld a, (apCount)
    cp c : jr c, .badNumber
    ; Locate entry number C
    ld hl, apList
    ld a, c : dec a : ld b, a
    jr z, .found
.skip
    call strEnd
    inc hl : inc hl : inc hl
    djnz .skip
.found
    ld de, ssidBuf : call strCopy    ; HL -> RSSI byte
    inc hl : ld a, (hl)              ; encryption
    ld hl, passBuf : ld (hl), 0
    and a : jr z, .connect           ; open network: no password
    Print passPrompt
    ld hl, passBuf : ld b, PASS_MAX : call Console.readPassword
    call Console.newLine
    jr c, .cancel
.connect
    ld hl, ssidBuf, de, passBuf
    jp connectTo
.cancel
    Print cancelled
    ret
.badNumber
    Print badNumber
    ret

manualConnect:
    Print ssidPrompt
    ld hl, inBuf : ld b, SSID_MAX : call Console.readString
    call Console.newLine
    and a : jr z, .cancel
    ld hl, inBuf + 2, de, ssidBuf : call strCopy
    Print passPromptOpen
    ld hl, passBuf : ld b, PASS_MAX : call Console.readPassword
    call Console.newLine
    jr c, .cancel
    ld hl, ssidBuf, de, passBuf
    jp connectTo
.cancel
    Print cancelled
    ret

; HL -> SSID, DE -> password
connectTo:
    push de, hl
    Print connecting
    pop hl
    call putQuoted
    Print pleaseWait
    pop de
    call Nifi.setAp
    and a : jr nz, .fail
    Print connectedMsg
    ld a, Nifi.IP_LOCAL : call Nifi.getIp
    and a : jr nz, .noIp
    ld (ipBuf), hl, (ipBuf + 2), de
    ld hl, ipBuf : call Console.dispIP
.noIp
    call Console.newLine
    Print savedMsg
    ret
.fail
    push af
    Print failedMsg
    pop af
    cp Nifi.ERR_AUTH_FAILED : jp nz, showError
    Print authHint
    ret

forgetNetwork:
    Print forgetConfirm
    call Console.getKey
    call toUpper
    cp 'Y' : jr nz, .no
    call Console.newLine
    call Nifi.forgetAp
    and a : jp nz, showError
    Print forgotten
    ret
.no
    call Console.newLine
    Print cancelled
    ret

;=====================================================================
; Firmware update (OTA)
;=====================================================================
; The repository is a plain HTTP(S) directory holding "version.txt" (the
; published version, first line) and "nifi.bin" (the firmware image). Its URL
; comes from NIFICFG.CFG ("UPDATE=url") or is typed here.
updateFirmware:
    Print updTitle
    Print stFirmware
    ld hl, buff : call Nifi.getVer
    and a : jr nz, .noVer
    Print buff
    jr .ver2
.noVer
    Print naMsg
.ver2
    call Console.newLine
    ld hl, infoBuf, de, buff : call Nifi.otaInfo
    and a : jr nz, .noInfo
    Print updFree
    ld hl, infoBuf + 8 : call dispKB
    Print updFree2
.noInfo
    call loadUpdateUrl
    ld a, (updUrl) : and a : jr nz, .haveUrl
    Print updAskUrl
    ld hl, urlIn : ld b, URL_MAX : call Console.readString
    call Console.newLine
    and a : jp z, .cancel
    ld hl, urlIn + 2, de, updUrl : call strCopy
.haveUrl
    ; make sure the URL ends with a slash
    ld hl, updUrl : call strEnd
    dec hl : ld a, (hl) : inc hl
    cp '/' : jr z, .slash
    ld (hl), '/' : inc hl : ld (hl), 0
.slash
    Print updRepo
    Print updUrl
    call Console.newLine

    ; Published version
    ld hl, updUrl, de, urlBuf : call strCopy
    dec de
    ld hl, verFile : call strCopy
    Print updChecking
    ld hl, urlBuf, de, buff : call Nifi.otaCheck
    and a : jr z, .gotVer
    call showError
    Print updNoVersion
    call Console.getKey : call toUpper
    call Console.newLine
    cp 'Y' : jp nz, .cancel
    jr .confirm
.gotVer
    Print updAvailable
    Print buff
    call Console.newLine
.confirm
    Print updConfirm
    call Console.getKey : call toUpper
    call Console.newLine
    cp 'Y' : jr nz, .cancel

    ld hl, updUrl, de, urlBuf : call strCopy
    dec de
    ld hl, binFile : call strCopy
    Print updWriting
    ld hl, urlBuf : call Nifi.otaUpdate
    and a : jr z, .ok
    cp Nifi.ERR_UPDATE : jr nz, .err
    Print updFailed
    Print Nifi.updateMsg
    jp Console.newLine
.err
    jp showError
.ok
    Print updDone
    ; give the modem a few seconds to reboot, then look for it again
    ld b, 240
.wait
    halt
    djnz .wait
    call Nifi.init : jr nz, .noAnswer
    Print updNewVer
    ld hl, buff : call Nifi.getVer
    and a : jr nz, .nl
    Print buff
.nl
    jp Console.newLine
.noAnswer
    Print updNoAnswer
    ret
.cancel
    Print cancelled
    ret

; Flashes the modem with an image read from disk (any DOS device: floppy,
; MegaFlashROM SD, Carnivore2, ...). The image goes to the modem in 1 KB
; blocks; the modem writes it to its spare OTA slot and only switches to it
; when the whole image arrived, so a failed transfer keeps the old firmware.
updateFromFile:
    Print updTitle
    Print stFirmware
    ld hl, buff : call Nifi.getVer
    and a : jr nz, .noVer
    Print buff
    jr .ver2
.noVer
    Print naMsg
.ver2
    call Console.newLine
    Print fileAsk
    ld hl, inBuf : ld b, 14 : call Console.readString
    call Console.newLine
    ld hl, inBuf + 2
    and a : jr nz, .copy
    ld hl, defBinName
.copy
    ld de, fileName : call strCopy
.named
    ld hl, fileName : call Dos.setName
    call Dos.open
    jr z, .opened
    Print fileNotFound
    Print fileName
    jp Console.newLine
.opened
    ; file size from the FCB (bytes 16-19)
    ld hl, (Dos.fcb + 16) : ld (imgSize), hl
    ld hl, (Dos.fcb + 18) : ld (imgSize + 2), hl
    Print fileSize
    ld hl, imgSize : call dispKB
    Print fileSize2
    ld hl, infoBuf, de, buff : call Nifi.otaInfo
    and a : jr nz, .confirm
    Print updFree
    ld hl, infoBuf + 8 : call dispKB
    Print updFree2
.confirm
    Print fileConfirm
    call Console.getKey : call toUpper
    call Console.newLine
    cp 'Y' : jr z, .start
    call Dos.close
    Print cancelled
    ret
.start
    ld hl, (imgSize), de, (imgSize + 2)
    call Nifi.otaBegin
    and a : jr nz, .updErr
    Print fileSending
    ld hl, 0 : ld (kbDone), hl
.loop
    ld hl, chunkBuf, bc, 1024
    call Dos.read
    ld a, b : or c : jr z, .eof
    ld hl, chunkBuf
    call Nifi.otaData
    and a : jr nz, .updErr
    ld hl, (kbDone) : inc hl : ld (kbDone), hl
    ld a, 13 : call Console.putC
    ld a, 2 : call Console.spaces
    call Console.dispDec16
    Print fileKb
    jr .loop
.eof
    call Dos.close
    call Console.newLine
    Print fileFinishing
    call Nifi.otaEnd
    and a : jr nz, .updErr2
    Print updDone
    ld b, 240
.wait
    halt
    djnz .wait
    call Nifi.init : jr nz, .noAnswer
    Print updNewVer
    ld hl, buff : call Nifi.getVer
    and a : jr nz, .nl
    Print buff
.nl
    jp Console.newLine
.noAnswer
    Print updNoAnswer
    ret
.updErr
    push af
    call Dos.close
    pop af
.updErr2
    push af
    call Nifi.otaAbort
    pop af
    cp Nifi.ERR_UPDATE : jr nz, .other
    Print updFailed
    Print Nifi.updateMsg
    jp Console.newLine
.other
    jp showError

; Reads "UPDATE=url" from NIFICFG.CFG into updUrl (empty when absent)
loadUpdateUrl:
    xor a : ld (updUrl), a
    ld hl, cfgName : call Dos.setName
    call Dos.open
    ret nz
    ld hl, cfgBuf, bc, CFG_MAX
    call Dos.read
    call Dos.close
    ld hl, cfgBuf
    add hl, bc
    ld (hl), 0
    ld hl, cfgBuf
.line
    ld a, (hl) : and a : ret z
    cp ' ' + 1 : jr nc, .text
    inc hl : jr .line
.text
    ld de, updKey
    push hl
.cmp
    ld a, (de) : and a : jr z, .match
    ld a, (hl) : call toUpper
    ld c, a : ld a, (de) : cp c : jr nz, .noMatch
    inc hl : inc de
    jr .cmp
.noMatch
    pop hl
.skip
    ld a, (hl) : and a : ret z
    inc hl
    cp 10 : jr z, .line
    jr .skip
.match
    pop de                     ; discard
    ld de, updUrl
    ld b, URL_MAX
.copy
    ld a, (hl)
    and a : jr z, .end
    cp 13 : jr z, .end
    cp 10 : jr z, .end
    cp ' ' : jr z, .end
    ld (de), a : inc de : inc hl
    djnz .copy
.end
    xor a : ld (de), a
    ret

; HL -> 32 bit value. Prints it in KB
dispKB:
    push hl
    inc hl
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
    srl h : rr l
    srl h : rr l
    call Console.dispDec16
    pop hl
    ret

;=====================================================================
; Helpers
;=====================================================================

; A -> error code. Prints "Error: <description>"
showError:
    push af
    Print errPrefix
    pop af
    cp Nifi.ERR_TIMEOUT : jr z, .timeout
    cp Nifi.ERR_HTTP : jr z, .http
    cp 21 : jr nc, .unknown
    ld hl, errTable
    ld e, a : ld d, 0
    add hl, de : add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    call Console.putStringZ
    jp Console.newLine
.unknown
    push af
    Print errUnknown
    pop af
    call Console.dispA
    jp Console.newLine
.timeout
    Print errTimeout
    jp Console.newLine
.http
    ld hl, (Nifi.httpStatus)
    ld a, h : or a : jr nz, .status
    ld a, l
    cp 3 : jr nc, .status
    ld hl, httpTable
    ld e, a : ld d, 0
    add hl, de : add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    call Console.putStringZ
    jp Console.newLine
.status
    push hl
    Print errHttp
    pop hl
    call Console.dispDec16
    jp Console.newLine

; A -> UART type (Uart.TYPE_*)
dispUartType:
    cp 4 : jr c, .known
    ld a, 3
.known
    ld hl, uartTable
    ld e, a : ld d, 0
    add hl, de : add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    jp Console.putStringZ

; A -> network state
dispNetState:
    cp 4 : jr c, .known
    ld a, 4
.known
    ld hl, stateTable
    ld e, a : ld d, 0
    add hl, de : add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    jp Console.putStringZ

; A -> encryption flag (0 open, 1 secured, other unknown). Prints 3 columns
dispEnc:
    cp 1 : jr z, .secured
    cp 2 : jr z, .unknown
    ld a, ' ' : jr .put
.secured
    ld a, '*' : jr .put
.unknown
    ld a, '?'
.put
    call Console.putC
    ld a, 2 : jp Console.spaces

; HL -> 6 bytes
dispMac:
    ld b, 6
.loop
    ld a, (hl) : call Console.dispHex
    inc hl
    dec b : ret z
    ld a, ':' : call Console.putC
    jr .loop

; HL -> string, printed between double quotes
putQuoted:
    ld a, '"' : call Console.putC
    call Console.putStringZ
    ld a, '"' : jp Console.putC

; HL -> string. HL <- its zero terminator
strEnd:
    ld a, (hl) : and a : ret z
    inc hl
    jr strEnd

; HL -> source, DE -> destination. Copies the terminator too.
; HL and DE <- byte after the terminator
strCopy:
    ld a, (hl) : ld (de), a
    inc hl : inc de
    and a : jr nz, strCopy
    ret

toUpper:
    cp 'a' : ret c
    cp 'z' + 1 : ret nc
    and #df
    ret

;=====================================================================
; Command line parsing
;=====================================================================
parseArgs:
    ld hl, #80
    ld a, (hl)
    ld c, a : ld b, 0
    inc hl
    ld de, cmdBuf
    and a : jr z, .term
    ldir
.term
    xor a : ld (de), a
    ld hl, cmdBuf
    call skipSpaces
    ld a, (hl) : and a : ret z
    cp '/' : jr z, .opt
    cp '-' : jr z, .opt
    ld a, 'C' : ld (mode), a         ; bare SSID means /C
    jr .tokens
.opt
    inc hl
    ld a, (hl) : call toUpper : ld (mode), a
    inc hl
.tokens
    call skipSpaces
    call token : ret z
    ld (argSsid), de
    call skipSpaces
    call token : ret z
    ld (argPass), de
    ret

skipSpaces:
    ld a, (hl) : cp ' ' : ret nz
    inc hl
    jr skipSpaces

; HL -> text. Isolates the next token (quoted or up to a space) in place.
; DE <- token (zero terminated), HL <- rest of the line. Z when no token.
token:
    ld a, (hl) : and a : ret z
    cp '"' : jr z, .quoted
    ld d, h : ld e, l
.plain
    ld a, (hl) : and a : jr z, .end
    cp ' ' : jr z, .cut
    inc hl
    jr .plain
.quoted
    inc hl
    ld d, h : ld e, l
.q
    ld a, (hl) : and a : jr z, .end
    cp '"' : jr z, .cut
    inc hl
    jr .q
.cut
    xor a : ld (hl), a
    inc hl
.end
    ld a, 1 : or a
    ret

;=====================================================================
; Texts
;=====================================================================
banner       db 13,10,"NiFi WiFi configuration utility 1.0",13,10
             db "For the NiFi ESP8266 modem - MSX-DOS",13,10
             db "(c) 2026 Andres Ortiz",13,10
             db "Based on NiFi by Nihirash (c) 2021",13,10
             db "and the UART code of Ducasp (c) 2020",13,10,13,10,0
initMsg      db "Looking for the modem... ",0
doneMsg      db "found",13,10,0
noModemMsg   db "not found",13,10,13,10
             db "The modem does not answer. Check that the cartridge is inserted,",13,10
             db "that the ESP8266 runs the NiFi firmware and that the UART port",13,10
             db "matches (UART_BASE in driver/uart.asm).",13,10,0

menuText     db 13,10
             db " 1. Network status",13,10
             db " 2. Scan and connect to a WiFi network",13,10
             db " 3. Connect typing the network name",13,10
             db " 4. Forget the stored network (disconnect)",13,10
             db " 5. Modem information",13,10
             db " 6. Update the modem firmware from the internet (OTA)",13,10
             db " 7. Update the modem firmware from a file on disk",13,10
             db " 0. Exit",13,10,13,10
             db "Choice: ",0
pressKey     db 13,10,"Press any key to return to the menu...",0

hdrNetwork   db "Network: ",0
hdrIp        db "   IP: ",0
hdrSignal    db "   Signal: ",0
notConnected db "not connected",0
hintConnect  db "Use option 2 to scan and connect to a network.",0

stFirmware   db "Firmware : ",0
stMac        db "MAC      : ",0
stLink       db "Link     : ",0
stNetwork    db "Network  : ",0
stSignal     db "Signal   : ",0
stUart       db "UART     : ",0
stUartPort   db " at port #",0
uartTable    dw u0, u1, u2, u3
u0  db "16C550C, FIFO, auto flow control (AFE) - supported",0
u1  db "16C550, FIFO, no auto flow control - NOT supported yet",0
u2  db "16C450/8250, no FIFO - not supported",0
u3  db "not found",0
uartWarning  db "Warning: the UART of this cartridge has no automatic flow",13,10
             db "control (16C550 instead of 16C550C). This version of the",13,10
             db "NiFi tools and driver needs the AFE version: transfers",13,10
             db "may lose data.",13,10,13,10,0
noUartMsg    db "No 16C550 UART found at port #80: check the cartridge or",13,10
             db "change UART_BASE in driver/uart.asm.",13,10,0
lblIp        db "IP       : ",0
lblMask      db "Netmask  : ",0
lblGw        db "Gateway  : ",0
lblDns1      db "DNS 1    : ",0
lblDns2      db "DNS 2    : ",0
naMsg        db "n/a",0
dbmMsg       db " dBm  ",0
infoText     db "Modem information",13,10,"-----------------",13,10,0

scanning     db "Scanning for networks (a few seconds)...",13,10,13,10,0
listHeader   db " #  Signal  S  SSID",13,10
             db "--  ------  -  --------------------------------",13,10,0
noNetworks   db "No networks found.",13,10,0
selectPrompt db 13,10,"'*' = password required",13,10
             db "Network number (0 = cancel): ",0
badNumber    db "There is no network with that number.",13,10,0
ssidPrompt   db "Network name (empty = cancel): ",0
passPrompt   db "Password (ESC = cancel): ",0
passPromptOpen db "Password (empty for open networks, ESC = cancel): ",0
cancelled    db "Cancelled.",13,10,0
connecting   db "Connecting to ",0
pleaseWait   db "... ",0
connectedMsg db "connected",13,10,"IP address: ",0
savedMsg     db "The network is stored in the modem and will be used",13,10
             db "automatically after power on.",13,10,0
failedMsg    db "failed",13,10,0
authHint     db "Error: could not join the network. Check the password",13,10
             db "and the signal strength.",13,10,0
forgetConfirm db "Forget the stored network and disconnect? (Y/N) ",0
forgotten    db "Stored network erased. The modem is disconnected.",13,10,0

missingSsid  db "Missing network name.",13,10,0
badOptionMsg db "Unknown option.",13,10,0
helpText     db 13,10,"Usage:",13,10
             db "  NIFICFG                 interactive menu",13,10
             db "  NIFICFG /S              show network status",13,10
             db "  NIFICFG /L              list the access points",13,10
             db "  NIFICFG /C ssid [pass]  connect (for AUTOEXEC.BAT)",13,10
             db "  NIFICFG /F              forget the stored network",13,10
             db "  NIFICFG /U              update the firmware (URL in NIFICFG.CFG)",13,10
             db "  NIFICFG /B [file]       update the firmware from a file (NIFI.BIN)",13,10
             db "  NIFICFG /?              this help",13,10,13,10
             db "Use double quotes for names with spaces.",13,10
             db "MSX-DOS 1 converts the command line to upper case:",13,10
             db "use the menu for case sensitive names or passwords.",13,10,0

updTitle     db "Firmware update",13,10,"---------------",13,10,0
updFree      db "OTA space: ",0
updFree2     db " KB free for the new image",13,10,0
updAskUrl    db "No UPDATE=url line in NIFICFG.CFG.",13,10
             db "Repository URL (empty = cancel): ",0
updRepo      db "Repository: ",0
updChecking  db "Reading version.txt... ",0
updNoVersion db "The published version could not be read. Flash nifi.bin anyway? (Y/N) ",0
updAvailable db "Published: ",0
updConfirm   db "Download nifi.bin and flash the modem? (Y/N) ",0
updWriting   db "Updating. Do not switch off the computer (one or two minutes)...",13,10,0
updFailed    db "Update failed: ",0
updDone      db "Image written. The modem is rebooting...",13,10,0
updNewVer    db "Running now: ",0
updNoAnswer  db "The modem does not answer after the update. Switch the",13,10
             db "computer off and on again.",13,10,0
updKey       db "UPDATE=",0
fileAsk      db "Image file [NIFI.BIN]: ",0
fileNotFound db "File not found: ",0
fileSize     db "Image size: ",0
fileSize2    db " KB",13,10,0
fileConfirm  db "Send the image to the modem and flash it? (Y/N) ",0
fileSending  db "Sending (one or two minutes, do not switch off)...",13,10,0
fileKb       db " KB sent",0
fileFinishing db "Activating the new image...",13,10,0
defBinName   db "NIFI.BIN",0
verFile      db "version.txt",0
binFile      db "nifi.bin",0
cfgName      db "NIFICFG.CFG",0

errPrefix    db "Error: ",0
errUnknown   db "unknown error code ",0
errTimeout   db "the modem did not answer in time",0
errHttp      db "the server answered HTTP ",0
httpTable    dw h0, h1, h2
h0  db "could not connect to the server",0
h1  db "the transfer failed",0
h2  db "too many redirects",0
errTable     dw e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13, e14, e15, e16, e17, e18, e19, e20
e0  db "no error",0
e1  db "not supported by this firmware",0
e2  db "no network connection",0
e3  db "no data available",0
e4  db "invalid parameter",0
e5  db "another query is in progress",0
e6  db "invalid IP address",0
e7  db "no DNS servers configured",0
e8  db "DNS error",0
e9  db "no free connections",0
e10 db "connection already exists",0
e11 db "connection does not exist",0
e12 db "invalid connection state",0
e13 db "insufficient buffer space",0
e14 db "datagram too large",0
e15 db "invalid operation",0
e16 db "authentication failed",0
e17 db "HTTP error",0
e18 db "bad zip file",0
e19 db "modem flash error",0
e20 db "firmware update failed",0

stateTable   dw s0, s1, s2, s3, s4
s0  db "down",0
s1  db "connecting",0
s2  db "up",0
s3  db "disconnecting",0
s4  db "unknown",0

ipLabels:
    dw lblIp   : db Nifi.IP_LOCAL
    dw lblMask : db Nifi.IP_MASK
    dw lblGw   : db Nifi.IP_GATEWAY
    dw lblDns1 : db Nifi.IP_DNS1
    dw lblDns2 : db Nifi.IP_DNS2

;=====================================================================
; Variables
;=====================================================================
mode     db 0
argSsid  dw 0
argPass  dw emptyStr
emptyStr db 0
apCount  db 0
ipBuf    ds 4
macBuf   ds 6
buff     ds 128
ssidBuf  ds 40
passBuf  ds 72
inBuf    ds 40
cmdBuf   ds 130
infoBuf  ds 12
imgSize  ds 4
kbDone   dw 0
fileName ds 16
chunkBuf ds 1024
updUrl   ds URL_MAX + 2
urlBuf   ds URL_MAX + 16
urlIn    ds URL_MAX + 3
cfgBuf   ds CFG_MAX + 1

apList   equ $
