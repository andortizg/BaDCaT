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

#ifndef EXCHANGE_H
#define EXCHANGE_H
#include "configuration.h"
char receive_buffer[MAX_FRAME];

void exchange_init();
unsigned char get_byte();
void publish_byte(char b);

unsigned int get_word() {
  char c1 = get_byte();
  return c1 | get_byte() << 8;
}

char* get_string() {
  for(int i=0;;i++) {
    unsigned char c = get_byte();
    // Keep the string inside the buffer no matter what the host sends
    if (i < MAX_FRAME - 1) receive_buffer[i] = c; else receive_buffer[MAX_FRAME - 1] = 0;
    if (c == 0) return receive_buffer;
  }
}

void get_block(unsigned int len, unsigned char *receive_buffer) {
  for (int i=0;i<len;i++)
    receive_buffer[i]=get_byte();

  return;
}


void publish_word(unsigned int w) {
   publish_byte(w & 255);
   publish_byte((w >> 8) & 255);
}

void publish_string(const char *str) {
  for (int i=0;str[i]!=0;i++)
    publish_byte(str[i]);

  publish_byte(0);
}

void publish_block(unsigned char *block, unsigned int len) {
  for (int i=0;i<len;i++)
    publish_byte(block[i]);
}

#endif
