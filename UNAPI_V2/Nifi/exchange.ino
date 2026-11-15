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

#include "exchange.h"
#include "configuration.h"
#include "connection_manager.h"
#include "ESP8266WiFi.h"

void exchange_init()
{
  Serial.begin(BAUDRATE, SERIAL_8N1);
  #ifdef ENABLE_FLOW
  pinMode(RTS_PIN, OUTPUT);
  pinMode(CTS_PIN, INPUT);
  digitalWrite(RTS_PIN, DEFAULT_RTS_LOW);
  #endif

}

unsigned char get_byte()
{
  #ifdef ENABLE_FLOW
  digitalWrite(RTS_PIN, DEFAULT_RTS_HIGH);
  #endif

  // The host drives the exchange, so the time spent waiting for the next
  // byte is the only moment to hand incoming connections to passive slots.
  while(Serial.available() < 1) {
    tcp_poll_listeners();
    yield();
  }

  #ifdef ENABLE_FLOW
  digitalWrite(RTS_PIN, DEFAULT_RTS_LOW);
  #endif

  return Serial.read();
}

void publish_byte(char b)
{
  while(Serial.availableForWrite() < 1) yield();
  #ifdef ENABLE_FLOW
  while (digitalRead(CTS_PIN) == DEFAULT_CTS_LOW) yield();
  #endif
  Serial.write(b);
  Serial.flush();
}
