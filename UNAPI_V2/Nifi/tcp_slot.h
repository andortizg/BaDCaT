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

#ifndef TCP_SLOT_H
#define TCP_SLOT_H

#include "ESP8266WiFi.h"
#include <lwip/tcp.h>
#include <string.h>
#include "configuration.h"
#include "protocol.h"

// One lwIP listening socket. Several passive UNAPI connections may share the
// same local port, so listeners are reference counted and kept apart from the
// connection slots.
struct TcpListener {
  WiFiServer server;
  unsigned int port;
  unsigned char refs;

  TcpListener() : server(0), port(0), refs(0) {}
};

// One UNAPI TCP connection (connection number = index + 1)
struct TcpSlot {
  WiFiClient client;
  bool listening;             // Passive connection waiting in LISTEN state
  bool resident;              // Not closed by "close all" (connection number 0)
  signed char listener;       // Index in the listener pool while listening, -1 otherwise
  unsigned char close_reason; // UNAPI close reason, reported once the connection is gone
  unsigned char expect_ip[4]; // Passive: accepted remote IP (0.0.0.0 = any)
  unsigned int expect_port;   // Passive: accepted remote port (0xFFFF = any)
  unsigned int local_port;

  TcpSlot() : listening(false), resident(false), listener(-1),
              close_reason(CLOSE_NEVER_USED), expect_port(0xffff), local_port(0) {
    memset(expect_ip, 0, sizeof(expect_ip));
  }
};

#endif
