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

; NETROM - load ROM images from internet repositories through the NiFi modem
;
;   NETROM                 interactive: pick a repository, browse, download
;   NETROM url/            browse a directory listing
;   NETROM url             download one file (zip files are unpacked by the modem)
;   NETROM /?              help
;
; Repositories come from NETROM.CFG (one "Name=URL" per line, '#' comments);
; without it a built-in list is used. The modem fetches the file (HTTPS,
; redirects and zip extraction happen there), then NETROM can save it to disk
; and/or start it from RAM (plain 8/16/32 KB cartridge images).
;
; Needs NiFi firmware 0.3 or later. Build: sjasmplus main.asm

    output "netrom.com"
    org #100
    jp start
    include "driver/uart.asm"
    include "driver/nifi.asm"
    include "driver/console.asm"
    include "driver/dos.asm"
    include "romboot.asm"

BDOS   = 5
_TERM0 = 0

PAGE_SIZE = 20          ; entries per screen
CHUNK     = 1024        ; bytes per UART block
MAX_REPOS = 9
URL_MAX   = 250
FILTER_MAX = 40

start:
    call parseArgs
    ld a, (mode)
    cp '?' : jp z, showHelp
    cp 'H' : jp z, showHelp

    Print banner
    Print initMsg
    call Nifi.init : jp nz, noModem
    Print doneMsg
    call Nifi.getNetState
    cp Nifi.NETSTATE_OPEN : jp nz, noNetwork
    call loadConfig

    ld hl, (argUrl)
    ld a, h : or l : jr z, repoMenu
    ; An URL on the command line: browse it or download it
    call strEnd
    dec hl
    ld a, (hl)
    inc hl
    ld hl, (argUrl)
    cp '/' : jr nz, .file
    call browse
    jp exit
.file
    call downloadUrl
    jp exit

;=====================================================================
; Repository menu
;=====================================================================
repoMenu:
    call Console.cls
    Print banner
    Print reposHeader
    ld hl, repoTable
    ld a, (repoCount)
    and a : jr z, .noRepos
    ld b, a
    ld c, '1'
.list
    ld a, ' ' : call Console.putC
    ld a, c : call Console.putC
    Print dotSpace
    ld e, (hl) : inc hl : ld d, (hl) : inc hl    ; name
    inc hl : inc hl                              ; skip url
    push hl
    ex de, hl : call Console.putStringZ
    call Console.newLine
    pop hl
    inc c
    djnz .list
    jr .footer
.noRepos
    Print noRepos
.footer
    Print reposFooter
.key
    call Console.getKey
    call toUpper
    cp 'U' : jr z, .typeUrl
    cp 'Q' : jp z, exit
    cp Console.KEY_ESC : jp z, exit
    sub '1' : jr c, .key
    ld c, a
    ld a, (repoCount)
    dec a
    cp c : jr c, .key
    ; repository C selected
    ld hl, repoTable
    ld b, c
    inc b : dec b : jr z, .found
.skip
    inc hl : inc hl : inc hl : inc hl
    djnz .skip
.found
    inc hl : inc hl
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    call Console.newLine
    call browse
    jp repoMenu
.typeUrl
    call Console.newLine
    Print urlPrompt
    ld hl, inBuf : ld b, URL_MAX : call Console.readString
    call Console.newLine
    and a : jp z, repoMenu
    ld hl, inBuf + 2
    call strEnd
    dec hl : ld a, (hl)
    ld hl, inBuf + 2
    cp '/' : jr nz, .typedFile
    call browse
    jp repoMenu
.typedFile
    call downloadUrl
    call pause
    jp repoMenu

;=====================================================================
; Listing browser
;=====================================================================

; HL -> URL of a directory. Returns when the user leaves the listing.
browse:
    push hl
    Print fetchingList
    pop hl
    call Nifi.listUrl
    and a : jr z, .ok
    call showError
    jp pause
.ok
    call resetView
browseLoop:
    call Console.cls
    ; Location line
    ld hl, urlBuf : call Nifi.getLocation
    call Console.width
    dec a
    ld b, a
    ld hl, urlBuf : call Console.putStringN
    call Console.newLine
    call Console.newLine

    ; Page of entries
    ld de, (pageStart)
    ld b, PAGE_SIZE
    ld hl, filterBuf
    ld ix, pageBuf
    call Nifi.listGet
    and a : jr z, .gotPage
    call showError
    call pause
    ret
.gotPage
    ld (total), de
    ld a, c : ld (shown), a
    and a : jr nz, .print
    Print noEntries
    jr .footer
.print
    ld hl, pageBuf
    ld b, 1
.entry
    push bc
    ld a, b : call Console.dispA2
    ld a, 2 : call Console.spaces
    inc hl : inc hl                              ; index
    ld a, (hl) : inc hl                          ; flags
    and Nifi.FLAG_DIR : jr z, .size
    push hl
    Print dirTag
    pop hl
    inc hl : inc hl : inc hl : inc hl
    jr .name
.size
    call dispSizeKB                              ; HL -> size, advances 4
.name
    ld a, 2 : call Console.spaces
    call Console.width
    sub 13
    ld b, a
    call Console.putStringN
    call Console.newLine
    call strEnd
    inc hl
    pop bc
    inc b
    ld a, (shown)
    cp b : jr nc, .entry
.footer
    call Console.newLine
    Print entriesMsg
    ld hl, (pageStart) : inc hl : call Console.dispDec16
    ld a, '-' : call Console.putC
    ld a, (shown) : ld e, a : ld d, 0
    ld hl, (pageStart) : add hl, de : call Console.dispDec16
    Print ofMsg
    ld hl, (total) : call Console.dispDec16
    ld a, (filterBuf) : and a : jr z, .noFilter
    Print filterTag
    ld hl, filterBuf : call Console.putStringZ
    ld a, ']' : call Console.putC
.noFilter
    call Console.newLine
    Print browsePrompt
    ld hl, inBuf : ld b, 3 : call Console.readString
    call Console.newLine
    ld a, (inBuf + 2)
    and a : jr z, .next                          ; empty line: next page
    cp '0' : jr c, .command
    cp '9' + 1 : jr nc, .command
    ld hl, inBuf + 2 : call Console.parseDec
    call openEntry
    jp browseLoop
.command
    call toUpper
    cp 'N' : jr z, .next
    cp 'P' : jr z, .prev
    cp 'U' : jr z, .up
    cp 'F' : jr z, .filter
    cp 'R' : ret z
    cp Console.KEY_ESC : ret z
    cp 'Q' : jp z, exit
    cp 'H' : jp z, .help
    cp '?' : jp z, .help
    jp browseLoop
.next
    ld a, (shown) : ld e, a : ld d, 0
    ld hl, (pageStart) : add hl, de
    ex de, hl
    ld hl, (total)
    and a : sbc hl, de                           ; total - next start
    jp z, browseLoop                             ; nothing beyond this page
    jp c, browseLoop
    ld (pageStart), de
    jp browseLoop
.prev
    ld hl, (pageStart)
    ld de, PAGE_SIZE
    and a : sbc hl, de
    jr nc, .prevOk
    ld hl, 0
.prevOk
    ld (pageStart), hl
    jp browseLoop
.up
    Print fetchingList
    call Nifi.listUp
    and a : jr z, .upOk
    cp Nifi.ERR_INV_OPER : jr nz, .upErr
    Print atTop
    call pause
    jp browseLoop
.upErr
    call showError
    call pause
    jp browseLoop
.upOk
    call resetView
    jp browseLoop
.filter
    Print filterPrompt
    ld hl, inBuf : ld b, FILTER_MAX : call Console.readString
    call Console.newLine
    ld hl, inBuf + 2, de, filterBuf : call strCopy
    ld hl, 0 : ld (pageStart), hl
    jp browseLoop
.help
    Print browseHelp
    call pause
    jp browseLoop

resetView:
    ld hl, 0 : ld (pageStart), hl
    xor a : ld (filterBuf), a
    ret

; A -> entry number on the screen (1..shown). Opens a directory or
; downloads a file.
openEntry:
    and a : ret z
    ld b, a
    ld a, (shown)
    cp b : ret c                                 ; beyond the list
    ld hl, pageBuf
    dec b : jr z, .found
.skip
    ld de, 7 : add hl, de
    call strEnd
    inc hl
    djnz .skip
.found
    ld e, (hl) : inc hl : ld d, (hl) : inc hl    ; DE = index
    ld a, (hl) : inc hl                          ; flags
    inc hl : inc hl : inc hl : inc hl            ; HL -> name
    and Nifi.FLAG_DIR : jr z, .file
    Print fetchingList
    call Nifi.listEnter
    and a : jr z, resetView
    call showError
    jp pause
.file
    call Console.newLine
    call downloadEntry
    jp pause

;=====================================================================
; Download, save, run
;=====================================================================

; DE -> entry index, HL -> entry name (for the message)
downloadEntry:
    push de, hl
    Print downloading
    pop hl
    call Console.putStringZ
    Print downloading2
    pop de
    ld hl, romName
    call Nifi.getEntry
    jr afterDownload

; HL -> URL
downloadUrl:
    push hl
    Print downloading
    pop hl
    push hl
    call Console.putStringZ
    Print downloading2
    pop hl
    ld de, romName
    call Nifi.getUrl
afterDownload:
    and a : jr z, .ok
    jp showError
.ok
    Print gotFile
    ld hl, romName : call Console.putStringZ
    Print gotSize
    ld hl, Nifi.romSize : call dispSizeKB
    Print gotSize2
actionMenu:
    Print actionPrompt
.key
    call Console.getKey
    call toUpper
    cp 'R' : jr z, .run
    cp 'S' : jr z, .save
    cp 'B' : jr z, .both
    cp Console.KEY_ESC : jr z, .cancel
    cp 'Q' : jr z, .cancel
    jr .key
.run
    call Console.newLine
    jp runRom
.save
    call Console.newLine
    call saveRom
    ret
.both
    call Console.newLine
    call saveRom
    jp runRom
.cancel
    call Console.newLine
    Print cancelled
    ret

; Loads the file into RAM and resets the machine so that the BIOS starts it
runRom:
    ; Header
    ld hl, 0 : ld (Nifi.fileOff), hl, (Nifi.fileOff + 2), hl
    ld bc, 16, hl, chunkBuf
    call Nifi.fileRead
    and a : jp nz, showError
    ld a, b : or a : jr nz, .header
    ld a, c : cp 16 : jr c, .tooSmall
.header
    ld hl, chunkBuf
    call RomBoot.placement
    and a : jr z, .load
    cp 1 : jr z, .noSig
    Print tooLarge
    ret
.noSig
    Print noSignature
    ret
.tooSmall
    Print noSignature
    ret
.load
    ld (loadAddr), de
    Print loadingAt
    ld a, d : call Console.dispHex
    ld a, e : call Console.dispHex
    Print loadingAt2
    ld hl, 0 : ld (Nifi.fileOff), hl, (Nifi.fileOff + 2), hl
    ld hl, 0 : ld (kbDone), hl
    ld hl, (loadAddr)
.loop
    push hl
    ld bc, CHUNK
    call Nifi.fileRead
    pop hl
    and a : jp nz, showError
    ld a, b : or c : jr z, .done
    add hl, bc
    ld a, h : cp #c0 : jr c, .inRange            ; must not go beyond page 2
    jr nz, .overflow
    ld a, l : or a : jr nz, .overflow
.inRange
    push hl
    call progress
    pop hl
    call checkEsc
    jr nc, .loop
    Print cancelled
    ret
.overflow
    Print tooLarge
    ret
.done
    call Console.newLine
    Print starting
    jp RomBoot.boot

; Saves the downloaded file to disk
saveRom:
    call proposeName
    Print namePrompt
    ld hl, defName : call Console.putStringZ
    Print namePrompt2
    ld hl, inBuf : ld b, 14 : call Console.readString
    call Console.newLine
    ld hl, inBuf + 2
    and a : jr nz, .named
    ld hl, defName
.named
    call Dos.setName
    call Dos.create
    jr z, .created
    Print cannotCreate
    ret
.created
    ld hl, 0 : ld (Nifi.fileOff), hl, (Nifi.fileOff + 2), hl
    ld hl, 0 : ld (kbDone), hl
    Print saving
.loop
    ld hl, chunkBuf
    ld bc, CHUNK
    call Nifi.fileRead
    and a : jr nz, .readErr
    ld a, b : or c : jr z, .done
    ld hl, chunkBuf
    call Dos.write
    jr nz, .diskFull
    call progress
    call checkEsc
    jr nc, .loop
    call Dos.close
    Print cancelled
    ret
.readErr
    push af
    call Dos.close
    pop af
    jp showError
.diskFull
    call Dos.close
    Print diskFull
    ret
.done
    call Dos.close
    call Console.newLine
    Print savedMsg
    ret

; Prints "\r  nnn / mmm KB" (kbDone counts CHUNK blocks)
progress:
    ld hl, (kbDone) : inc hl : ld (kbDone), hl
    ld a, 13 : call Console.putC
    ld a, 2 : call Console.spaces
    ld b, 5 : call Console.dispDec16W
    Print ofSlash
    ld hl, Nifi.romSize : call dispSizeKB
    Print kbMsg
    ret

; C flag when ESC was pressed
checkEsc:
    call Console.keyAvailable
    ret z
    call Console.getKey
    cp Console.KEY_ESC
    scf : ret z
    and a
    ret

; Builds defName ("XXXXXXXX.ROM") from romName
proposeName:
    ld hl, romName, de, defName
    ld b, 8
.loop
    ld a, (hl)
    and a : jr z, .ext
    inc hl
    cp '.' : jr z, .ext                          ; stop at the extension
    call toUpper
    cp '0' : jr c, .loop
    cp '9' + 1 : jr c, .take
    cp 'A' : jr c, .loop
    cp 'Z' + 1 : jr nc, .loop
.take
    ld (de), a : inc de
    djnz .loop
.ext
    ld a, b : cp 8 : jr nz, .ok
    ld a, 'R' : ld (de), a : inc de              ; empty name: "ROM.ROM"
    ld a, 'O' : ld (de), a : inc de
    ld a, 'M' : ld (de), a : inc de
.ok
    ld hl, romExt
    jp strCopy

; HL -> 4 byte size. Prints it in KB (4 columns + 'K', "   ?" when zero).
; HL <- after the 4 bytes.
dispSizeKB:
    push bc, de
    ld e, (hl) : inc hl
    ld c, (hl) : inc hl
    ld b, (hl) : inc hl
    ld a, (hl) : inc hl
    or b : or c : or e
    jr z, .unknown
    ld a, c : and 3 : or e : ld d, a             ; D <> 0: round up
    push hl
    ld h, b : ld l, c
    srl h : rr l
    srl h : rr l
    ld a, d : and a : jr z, .exact
    inc hl
.exact
    ld b, 4 : call Console.dispDec16W
    pop hl
    ld a, 'K' : call Console.putC
    pop de, bc
    ret
.unknown
    push hl
    Print unknownSize
    pop hl
    pop de, bc
    ret

;=====================================================================
; Configuration file
;=====================================================================
loadConfig:
    ld hl, cfgName : call Dos.setName
    call Dos.open
    jp nz, .defaults
    ld hl, cfgBuf, bc, CFG_MAX
    call Dos.read
    call Dos.close
    ld hl, cfgBuf
    add hl, bc
    ld (hl), 0
    ld hl, cfgBuf
    ld ix, repoTable
    xor a : ld (repoCount), a
.line
    ld a, (hl)
    and a : ret z
    cp ' ' + 1 : jr nc, .text                    ; control chars and spaces
    inc hl
    jr .line
.text
    cp '#' : jr z, .skipLine
    ld (ix + 0), l : ld (ix + 1), h              ; name
.findEq
    ld a, (hl)
    and a : ret z
    cp 13 : jr z, .skipLine
    cp 10 : jr z, .skipLine
    cp '=' : jr z, .eq
    inc hl
    jr .findEq
.eq
    ld (hl), 0
    inc hl
.spaces
    ld a, (hl) : cp ' ' : jr nz, .url
    inc hl : jr .spaces
.url
    ld (ix + 2), l : ld (ix + 3), h
.findEol
    ld a, (hl)
    and a : jr z, .last
    cp 13 : jr z, .eol
    cp 10 : jr z, .eol
    inc hl
    jr .findEol
.eol
    ld (hl), 0
    inc hl
.last
    push hl
    dec hl
.trim
    ld a, (hl) : cp ' ' : jr nz, .trimmed
    ld (hl), 0 : dec hl
    jr .trim
.trimmed
    pop hl
    ld a, (repoCount) : inc a : ld (repoCount), a
    cp MAX_REPOS : ret nc
    ld de, 4
    add ix, de
    jr .line
.skipLine
    ld a, (hl)
    and a : ret z
    inc hl
    cp 10 : jr z, .line
    jr .skipLine
.defaults
    ld hl, defaultRepos, de, repoTable, bc, defaultReposEnd - defaultRepos
    ldir
    ld a, (defaultReposEnd - defaultRepos) / 4
    ld (repoCount), a
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
    cp 20 : jr nc, .unknown
    ld hl, errTable
    ld e, a : ld d, 0
    add hl, de : add hl, de
    ld e, (hl) : inc hl : ld d, (hl)
    ex de, hl
    call Console.putStringZ
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
.unknown
    push af
    Print errUnknown
    pop af
    call Console.dispA
    jp Console.newLine

pause:
    Print pressKey
    call Console.getKey
    jp Console.newLine

; HL -> string. HL <- its zero terminator
strEnd:
    ld a, (hl) : and a : ret z
    inc hl
    jr strEnd

; HL -> source, DE -> destination. Copies the terminator too.
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
.skip
    ld a, (hl) : cp ' ' : jr nz, .start
    inc hl : jr .skip
.start
    and a : ret z
    cp '/' : jr z, .opt
    cp '-' : jr z, .opt
    ld (argUrl), hl
.cut
    ld a, (hl) : and a : ret z
    cp ' ' : jr z, .end
    inc hl : jr .cut
.end
    xor a : ld (hl), a
    ret
.opt
    inc hl
    ld a, (hl) : call toUpper : ld (mode), a
    ret

noModem:
    Print noModemMsg
    jp exit
noNetwork:
    Print noNetworkMsg
    jp exit
showHelp:
    Print banner
    Print helpText
exit:
    ld c, _TERM0
    jp BDOS

;=====================================================================
; Texts
;=====================================================================
banner       db "NETROM 1.0 - ROM loader for the NiFi modem (MSX-DOS)",13,10
             db "(c) 2026 Andres Ortiz",13,10
             db "Based on NiFi by Nihirash (c) 2021",13,10
             db "and the UART code of Ducasp (c) 2020",13,10,13,10,0
initMsg      db "Looking for the modem... ",0
doneMsg      db "found",13,10,0
noModemMsg   db "not found",13,10,13,10
             db "The modem does not answer. Check the cartridge, the firmware",13,10
             db "(0.3 or later) and UART_BASE in driver/uart.asm.",13,10,0
noNetworkMsg db "The modem is not connected to a WiFi network.",13,10
             db "Run NIFICFG to connect first.",13,10,0

reposHeader  db "Repositories (NETROM.CFG):",13,10,13,10,0
noRepos      db " (none)",13,10,0
reposFooter  db 13,10," U. Type an URL",13,10," Q. Quit",13,10,13,10,"Choice: ",0
dotSpace     db ". ",0
urlPrompt    db "URL (ending with / for a listing): ",0

fetchingList db "Fetching the listing...",13,10,0
noEntries    db " (no entries)",13,10,0
dirTag       db "<DIR>",0
unknownSize  db "   ?K",0
entriesMsg   db "Entries ",0
ofMsg        db " of ",0
filterTag    db "  [filter: ",0
browsePrompt db "Number to open, N P U F R Q (H=help): ",0
atTop        db "Already at the top of this repository.",13,10,0
filterPrompt db "Show only names containing (empty = all): ",0
browseHelp   db 13,10
             db " number  open the directory / download the file",13,10
             db " N or empty line  next page      P  previous page",13,10
             db " U  parent directory              F  filter by text",13,10
             db " R  back to the repository list   Q  quit",13,10,0

downloading  db "Downloading ",0
downloading2 db 13,10,"(the modem fetches and unpacks the file, please wait)",13,10,0
gotFile      db "File: ",0
gotSize      db " (",0
gotSize2     db "B)",13,10,0
actionPrompt db 13,10,"R)un from RAM   S)ave to disk   B)oth   ESC: ",0
cancelled    db "Cancelled.",13,10,0
tooLarge     db "This image is larger than 32 KB (MegaROM or 48/64 KB ROM).",13,10
             db "It cannot be started from RAM: save it and use a MegaROM",13,10
             db "device with SofaRun or a similar loader.",13,10,0
noSignature  db "No cartridge signature (AB) at the start of the file: this is",13,10
             db "not a plain cartridge image. Save it instead.",13,10,0
loadingAt    db "Loading into RAM at ",0
loadingAt2   db "h (ESC = cancel)",13,10,0
starting     db "Starting the ROM...",13,10,0
namePrompt   db "File name [",0
namePrompt2  db "]: ",0
cannotCreate db "Cannot create the file.",13,10,0
saving       db "Saving (ESC = cancel)",13,10,0
diskFull     db 13,10,"Disk full or write error.",13,10,0
savedMsg     db "Saved.",13,10,0
ofSlash      db " / ",0
kbMsg        db "B ",0
romExt       db ".ROM",0
cfgName      db "NETROM.CFG",0
pressKey     db "Press any key...",0

helpText     db "Usage:",13,10
             db "  NETROM          interactive (repositories from NETROM.CFG)",13,10
             db "  NETROM url/     browse a directory listing",13,10
             db "  NETROM url      download one file",13,10
             db "  NETROM /?       this help",13,10,13,10
             db "NETROM.CFG: one repository per line, 'Name=URL'.",13,10
             db "MSX-DOS 1 upper-cases the command line: type URLs in the",13,10
             db "menu (U) or put them in NETROM.CFG.",13,10,0

errPrefix    db "Error: ",0
errUnknown   db "unknown error code ",0
errTimeout   db "the modem did not answer in time",0
errHttp      db "the server answered HTTP ",0
errTable     dw e0, e1, e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12, e13, e14, e15, e16, e17, e18, e19
e0  db "no error",0
e1  db "not supported by this firmware (0.3 or later is needed)",0
e2  db "no network connection",0
e3  db "no file was downloaded",0
e4  db "invalid parameter (bad URL or entry)",0
e5  db "another query is in progress",0
e6  db "invalid IP address",0
e7  db "no DNS servers configured",0
e8  db "DNS error",0
e9  db "no free connections",0
e10 db "connection already exists",0
e11 db "connection does not exist",0
e12 db "invalid connection state",0
e13 db "the modem is out of memory",0
e14 db "the file is too large for the modem flash",0
e15 db "invalid operation",0
e16 db "authentication failed",0
e17 db "HTTP error",0
e18 db "bad zip file (corrupt, unsupported or without a ROM inside)",0
e19 db "modem flash error (no file system? check the Flash Size option)",0
httpTable    dw h0, h1, h2
h0  db "could not connect to the server",0
h1  db "the transfer failed",0
h2  db "too many redirects",0

; Built-in repositories: name pointer, URL pointer
defaultRepos:
    dw rn1, ru1
    dw rn2, ru2
    dw rn3, ru3
    dw rn4, ru4
defaultReposEnd:
rn1 db "file-hunter - MSX1 ROM",0
ru1 db "https://download.file-hunter.com/Games/MSX1/ROM/",0
rn2 db "file-hunter - MSX2 ROM",0
ru2 db "https://download.file-hunter.com/Games/MSX2/ROM/",0
rn3 db "TOSEC - MSX Games [ROM]",0
ru3 db "https://archive.org/download/TOSEC_2020_Roundup/MSX/MSX/Games/%5BROM%5D/"
    db "MSX%20MSX%20-%20Games%20-%20%5BROM%5D%20%28TOSEC-v2012-04-15%29.zip/",0
rn4 db "TOSEC - MSX (browse all)",0
ru4 db "https://archive.org/download/TOSEC_2020_Roundup/MSX/",0

;=====================================================================
; Variables
;=====================================================================
CFG_MAX  = 2047
mode      db 0
argUrl    dw 0
repoCount db 0
repoTable ds MAX_REPOS * 4
pageStart dw 0
total     dw 0
shown     db 0
loadAddr  dw 0
kbDone    dw 0
filterBuf ds FILTER_MAX + 1
defName   ds 16
romName   ds 80
inBuf     ds URL_MAX + 3
cmdBuf    ds 130
urlBuf    ds 256
chunkBuf  ds CHUNK
pageBuf   ds PAGE_SIZE * 88
cfgBuf    ds CFG_MAX + 1
end:
    assert end < #4000
