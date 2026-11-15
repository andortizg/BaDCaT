// NiFi UNAPI V2 - ESP8266 firmware, UNAPI driver and MSX-DOS tools
// for the BadCat WiFi cartridge.
//
// Copyright (C) 2026 Andrés Ortiz
// Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander
// Sharihin), Copyright (C) 2021, https://github.com/nihirash/esp-binary-firmware
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// ROM loader: HTTP(S) downloads to the ESP flash file system, zip extraction
// and directory listings for the NETROM utility (commands 0x40-0x47).
#ifndef ROMLOADER_H
#define ROMLOADER_H

void romloader_init();

void http_list_url();       // 0x40: fetch and parse the listing of an URL
void http_list_get();       // 0x41: page of the current listing (with filter)
void http_list_enter();     // 0x42: list a directory entry of the current listing
void http_list_up();        // 0x43: list the parent of the current location
void http_get_entry();      // 0x44: download a file entry (unzipped) to flash
void http_get_url();        // 0x45: download an URL (unzipped) to flash
void file_read();           // 0x46: read a block of the downloaded file
void http_get_location();   // 0x47: current location URL

void ota_check();           // 0x50: read a short text file (published version) from an URL
void ota_update();          // 0x51: flash a firmware binary from an URL and reboot
void ota_info();            // 0x52: flash chip size, sketch size, free OTA space
void ota_begin();           // 0x53: start receiving an image from the host
void ota_data();            // 0x54: image block
void ota_end();             // 0x55: finish, activate and reboot
void ota_abort();           // 0x56: discard the image received so far

#endif
