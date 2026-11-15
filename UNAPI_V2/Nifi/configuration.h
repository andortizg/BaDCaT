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

#ifndef CONFIGURATION_H
#define CONFIGURATION_H

#define MAGIC_STR "NiFi"
#define VERSION "0.3"

// UART
#define BAUDRATE 115200
#define ENABLE_FLOW
#define CTS_PIN 5
#define RTS_PIN 4

# define DEFAULT_CTS_HIGH  LOW
# define DEFAULT_CTS_LOW  HIGH

# define DEFAULT_RTS_HIGH  LOW
# define DEFAULT_RTS_LOW  HIGH

// Exchange props
#define MAX_FRAME 1300

// TCP
#define IS_NO_DELAY true
#define IS_SYNC true
#define MAX_SOCKETS 8
// Default timeout (ms) for an active open when the UNAPI user timeout is 0
#define DEFAULT_CONNECT_TIMEOUT 10000
// Upper bound (ms) for an active open when the UNAPI user timeout is #FFFF ("infinite")
#define MAX_CONNECT_TIMEOUT 120000
// Pending (not yet accepted) clients per listening port
#define LISTEN_BACKLOG 2

// UDP
#define MAX_UDP_SOCKETS 4

// ROM loader (HTTP downloads to the flash file system, see romloader.ino).
// The board must be built with a LittleFS partition ("Flash Size" option in
// the Arduino IDE, e.g. "4MB (FS:2MB OTA:~1019KB)").
// Largest file accepted (compressed or not), limited anyway by the free flash
#define MAX_ROM_DOWNLOAD (2UL * 1024UL * 1024UL)
// Connection / read timeout for HTTP transfers (ms)
#define HTTP_TIMEOUT 20000
// Some download sites refuse clients that do not identify themselves
#define HTTP_USER_AGENT "Mozilla/5.0 (compatible; NiFi-MSX/" VERSION "; ESP8266)"
#endif
