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

// Small streaming DEFLATE (RFC 1951) decoder and CRC-32 helper.
//
// Written for the NiFi ROM loader: zip entries downloaded from the internet
// are inflated from the ESP flash file system to the MSX. The decoder reads
// its input one byte at a time through a callback and hands the output to
// another callback in blocks, keeping a 32 KB sliding window supplied by the
// caller, so it needs no other memory. It follows the structure of Mark
// Adler's "puff" reference decoder.
//
// This file has no Arduino dependencies, so it can be compiled and tested on
// a PC (see tester/inflate_test.cpp).
#ifndef NIFI_INFLATE_H
#define NIFI_INFLATE_H

#include <stdint.h>
#include <stddef.h>

#define INFLATE_WINDOW_SIZE 32768

// Returns the next input byte (0..255) or -1 when no more input is available.
typedef int (*inflate_in_cb)(void *ctx);
// Receives decoded data. Returns false to abort the decompression.
typedef bool (*inflate_out_cb)(void *ctx, const uint8_t *data, size_t len);

enum InflateResult {
  INFLATE_OK          = 0,
  INFLATE_ERR_INPUT   = -1,   // input ended before the stream was complete
  INFLATE_ERR_DATA    = -2,   // corrupt or unsupported stream
  INFLATE_ERR_OUTPUT  = -3,   // the output callback asked to stop
  INFLATE_ERR_WINDOW  = -4    // no window buffer supplied
};

struct InflateStats {
  uint32_t in_bytes;    // compressed bytes consumed (exact: no read-ahead)
  uint32_t out_bytes;   // decompressed bytes produced
};

// Decodes one raw DEFLATE stream (no zlib or gzip header).
// window must point to INFLATE_WINDOW_SIZE bytes.
int inflate_stream(inflate_in_cb in, inflate_out_cb out, void *ctx,
                   uint8_t *window, InflateStats *stats);

// Standard CRC-32 (zip, gzip, PNG). Start with 0 and feed consecutive blocks.
uint32_t crc32_update(uint32_t crc, const uint8_t *data, size_t len);

#endif
