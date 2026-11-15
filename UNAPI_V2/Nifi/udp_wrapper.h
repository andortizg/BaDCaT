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

#ifndef UDP_WRAPPER_H
#define UDP_WRAPPER_H
#include "WiFiUdp.h"
#include "ESP8266WiFi.h"

class UdpWrapper {
  public:
    // Fields
    bool is_opened;
    bool is_parsed;
    unsigned int port;
    WiFiUDP udp;
    // Constructor
    UdpWrapper() {
      is_opened = false;
      is_parsed = false;
      udp = WiFiUDP();
    }

};

#endif
