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

#ifndef CONNECTION_MANAGER_H
#define CONNECTION_MANAGER_H
#include "protocol.h"

// TCP
unsigned char get_total_sockets();
unsigned char get_free_sockets();

bool tcp_slot_in_use(int i);
unsigned char tcp_slot_state(int i);
unsigned char tcp_slot_close_reason(int i);
void tcp_poll_listeners();

void open_tcp(char *addr, unsigned int port);   // Legacy active open (IP + port)
void open_tcp_ex();                              // UNAPI parameter block (active / passive)
void close_tcp(unsigned char n, bool abort);
void close_tcp_all();

// UDP
unsigned char get_total_udp_sockets();
unsigned char get_free_udp_sockets();

void open_udp(unsigned int port);
void close_udp(char n);
void close_udp_all();

#endif
