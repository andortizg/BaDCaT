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

#include "configuration.h"
#include "ESP8266WiFi.h"
#include "tcp_slot.h"

const char version_str[] = MAGIC_STR " " VERSION " " __DATE__ " " __TIME__;

#include "exchange.h"
#include "protocol.h"
#include "connection_manager.h"
#include "netman.h"
#include "romloader.h"

void perform_reset() {
  close_tcp_all();
  close_udp_all();
  publish_byte(ERR_OK);
  publish_string(MAGIC_STR);
}

void setup() {
  exchange_init();
  netman_init();
  romloader_init();
}

void loop() {
  process_operation();
}
