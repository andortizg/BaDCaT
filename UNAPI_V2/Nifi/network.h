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

#ifndef NETWORK_H
#define NETWORK_H

#include "connection_manager.h"
#include "configuration.h"
#include "tcp_slot.h"
#include "udp_wrapper.h"

extern TcpSlot pool[MAX_SOCKETS];
extern TcpListener listeners[MAX_SOCKETS];
extern UdpWrapper udp_pool[MAX_UDP_SOCKETS];

void resolve_request(char *domain);

// TCP
void tcp_status(unsigned char n);
void tcp_ext_status(unsigned char n);
void tcp_send(unsigned char n, unsigned int bs);
void tcp_recv(unsigned char n, unsigned int bs);

// UDP
void udp_status(char n);
void upd_send(char n);
void udp_recv(char n, unsigned int bs);
#endif
