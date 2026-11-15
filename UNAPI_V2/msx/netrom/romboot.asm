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

; Starts a cartridge ROM image that was loaded into RAM at 4000h-BFFFh.
;
; The MSX BIOS scans every slot for the "AB" cartridge signature at 4000h and
; 8000h when it boots. Under MSX-DOS pages 1 and 2 (4000h-BFFFh) are RAM
; that is not touched by a soft reset, so a ROM copied there is found and
; started exactly like a real cartridge once we jump to the BIOS reset
; entry. This is the technique used by the classic ROM loaders: it works for
; plain 8/16/32 KB cartridges (no mapper) that live in pages 1-2.
;
; Steps:
;   1. interrupts off, private stack in page 0
;   2. if primary slot 0 is expanded and its page 0 does not show subslot 0
;      (the main ROM), the secondary slot register of slot 0 (at FFFFh) has
;      to be changed. When the RAM of page 3 is in slot 0 the stub below does
;      it; otherwise it is done from here, selecting slot 0 in page 3 for a
;      moment (this code runs in page 0, which is not changed)
;   3. copy a small stub to page 3 (RAM in every configuration)
;   4. the stub selects slot 0 in page 0 and jumps to 0000h (BIOS reset)
    module RomBoot

EXPTBL = #fcc1       ; expanded slot flags (bit 7) for primary slots 0-3
SLTTBL = #fcc5       ; current value of the secondary slot registers
RAMAD3 = #f344       ; slot of the RAM in page 3
STUB   = #f000       ; RAM in page 3 (anything there dies with the reset anyway)

; HL -> ROM image header (first 16 bytes). Decides where the image must be
; loaded. A <- 0 and DE <- load address (4000h or 8000h), or A <- error:
;   1 = no "AB" signature, 2 = too large for RAM loading (over 32 KB)
; (Nifi.romSize) must contain the file size.
; (Decision rule of the common emulators for 8/16 KB ROMs: the INIT, or TEXT
;  when INIT is zero, address tells whether the image belongs to 4000h or
;  8000h. Images of 32 KB always go to 4000h.)
placement:
    ld a, (Nifi.romSize + 2) : or a : jr nz, .large
    ld a, (Nifi.romSize + 3) : or a : jr nz, .large
    ld a, (Nifi.romSize + 1)
    cp #81 : jr nc, .large           ; > 32768
    cp #80 : jr nz, .size
    ld a, (Nifi.romSize) : or a : jr nz, .large
.size
    ex de, hl                        ; DE = header
    ld a, (de) : cp 'A' : jr nz, .noSig
    inc de : ld a, (de) : cp 'B' : jr nz, .noSig
    dec de
    ld a, (Nifi.romSize + 1)
    cp #41 : jr nc, .at4000          ; more than 16 KB: 4000h
    ; INIT (or TEXT) decides
    ld hl, 2 : add hl, de
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
    ld a, h : or l : jr nz, .check
    ld hl, 8 : add hl, de
    ld a, (hl) : inc hl : ld h, (hl) : ld l, a
.check
    ld a, h
    cp #80 : jr c, .at4000
    cp #c0 : jr nc, .at4000
    ld de, #8000
    xor a
    ret
.at4000
    ld de, #4000
    xor a
    ret
.noSig
    ld a, 1
    ret
.large
    ld a, 2
    ret

; Never returns. Resets the machine so that the BIOS starts the ROM in RAM.
boot:
    di
    ld sp, localStack
    in a, (#a8) : ld b, a                      ; B = current primary slots
    ld c, 0                                    ; C = secondary value for the stub
    ld d, 0                                    ; D = 1: the stub writes FFFFh

    ; Step 2: does slot 0 need its page 0 pointed to subslot 0?
    ld a, (EXPTBL) : and #80 : jr z, .copy     ; slot 0 not expanded
    ld a, (SLTTBL) : and 3 : jr z, .copy       ; already subslot 0
    ld a, (SLTTBL) : and #fc : ld c, a         ; new register value
    ld a, (RAMAD3) : and 3 : jr nz, .fromHere
    ld d, 1                                    ; page 3 is slot 0: stub does it
    jr .copy
.fromHere
    ld a, b : and #3f : out (#a8), a           ; page 3 -> primary slot 0
    ld a, c : ld (#ffff), a
    ld a, b : out (#a8), a                     ; page 3 -> RAM again

.copy
    ; Step 3: stub to page 3
    ld hl, stub, de, STUB, bc, stubEnd - stub
    ldir
    ; Step 4
    ld a, b
    and #fc                                    ; page 0 -> primary slot 0
    jp STUB

; Relocatable: A = new primary register, C = secondary value, D = write flag
stub:
    inc d : dec d : jr z, .go
    ld e, a
    ld a, c : ld (#ffff), a
    ld a, e
.go
    out (#a8), a
    jp 0
stubEnd:

    ds 32
localStack:

    endmodule
