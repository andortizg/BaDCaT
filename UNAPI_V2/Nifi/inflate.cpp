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

// Streaming DEFLATE decoder, see inflate.h.
#include "inflate.h"

#define MAXBITS   15      // maximum bits in a code
#define MAXLCODES 286     // maximum number of literal/length codes
#define MAXDCODES 30      // maximum number of distance codes
#define MAXCODES  (MAXLCODES + MAXDCODES)
#define FIXLCODES 288     // number of fixed literal/length codes
#define WMASK     (INFLATE_WINDOW_SIZE - 1)

struct Huffman {
  short *count;   // number of symbols of each length
  short *symbol;  // canonically ordered symbols
};

struct State {
  inflate_in_cb in;
  inflate_out_cb out;
  void *ctx;
  uint8_t *window;
  uint32_t wpos;      // total bytes produced (window index = wpos & WMASK)
  uint32_t flushed;   // bytes already handed to the output callback
  uint32_t in_bytes;
  int bitbuf;
  int bitcnt;
  int error;          // sticky error code
};

// ---------------------------------------------------------------- input

static int bits(State *s, int need) {
  long val = s->bitbuf;
  while (s->bitcnt < need) {
    int c = s->in(s->ctx);
    if (c < 0) { s->error = INFLATE_ERR_INPUT; return 0; }
    s->in_bytes++;
    val |= (long)(c & 0xff) << s->bitcnt;
    s->bitcnt += 8;
  }
  s->bitbuf = (int)(val >> need);
  s->bitcnt -= need;
  return (int)(val & ((1L << need) - 1));
}

// ---------------------------------------------------------------- output

// Hands the part of the window not yet delivered to the output callback.
static bool flush(State *s) {
  while (s->flushed < s->wpos) {
    uint32_t start = s->flushed & WMASK;
    uint32_t len = s->wpos - s->flushed;
    if (len > INFLATE_WINDOW_SIZE - start) len = INFLATE_WINDOW_SIZE - start;
    if (!s->out(s->ctx, s->window + start, len)) { s->error = INFLATE_ERR_OUTPUT; return false; }
    s->flushed += len;
  }
  return true;
}

static inline bool put(State *s, uint8_t b) {
  s->window[s->wpos & WMASK] = b;
  s->wpos++;
  // Flush whenever the window fills up, before the oldest byte is overwritten
  if ((s->wpos & WMASK) == 0) return flush(s);
  return true;
}

// ---------------------------------------------------------------- huffman

static int decode(State *s, const Huffman *h) {
  int code = 0, first = 0, index = 0;
  for (int len = 1; len <= MAXBITS; len++) {
    code |= bits(s, 1);
    if (s->error) return -1;
    int count = h->count[len];
    if (code - count < first) return h->symbol[index + (code - first)];
    index += count;
    first += count;
    first <<= 1;
    code <<= 1;
  }
  return -10;   // ran out of codes
}

// Builds the canonical code from the code lengths. Returns 0 for a complete
// code, a positive value for an incomplete one and a negative value when the
// lengths are over-subscribed.
static int construct(Huffman *h, const short *length, int n) {
  int offs[MAXBITS + 1];

  for (int len = 0; len <= MAXBITS; len++) h->count[len] = 0;
  for (int symbol = 0; symbol < n; symbol++) h->count[length[symbol]]++;
  if (h->count[0] == n) return 0;   // no codes at all

  int left = 1;
  for (int len = 1; len <= MAXBITS; len++) {
    left <<= 1;
    left -= h->count[len];
    if (left < 0) return left;
  }

  offs[1] = 0;
  for (int len = 1; len < MAXBITS; len++) offs[len + 1] = offs[len] + h->count[len];

  for (int symbol = 0; symbol < n; symbol++)
    if (length[symbol] != 0) h->symbol[offs[length[symbol]]++] = symbol;

  return left;
}

// ---------------------------------------------------------------- blocks

static const short lbase[29] = {
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
static const short lext[29] = {
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
static const short dbase[30] = {
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
  8193, 12289, 16385, 24577 };
static const short dext[30] = {
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

// Decodes literal/length and distance pairs until the end-of-block code
static int codes(State *s, const Huffman *lencode, const Huffman *distcode) {
  for (;;) {
    int symbol = decode(s, lencode);
    if (s->error) return s->error;
    if (symbol < 0) return INFLATE_ERR_DATA;

    if (symbol < 256) {
      if (!put(s, (uint8_t) symbol)) return s->error;
    } else if (symbol == 256) {
      return INFLATE_OK;
    } else {
      symbol -= 257;
      if (symbol >= 29) return INFLATE_ERR_DATA;
      int len = lbase[symbol] + bits(s, lext[symbol]);
      if (s->error) return s->error;

      symbol = decode(s, distcode);
      if (s->error) return s->error;
      if (symbol < 0 || symbol >= 30) return INFLATE_ERR_DATA;
      uint32_t dist = (uint32_t) dbase[symbol] + (uint32_t) bits(s, dext[symbol]);
      if (s->error) return s->error;
      if (dist > s->wpos) return INFLATE_ERR_DATA;   // distance before the start of output

      while (len--) {
        uint8_t b = s->window[(s->wpos - dist) & WMASK];
        if (!put(s, b)) return s->error;
      }
    }
  }
}

static int stored(State *s) {
  s->bitbuf = 0;
  s->bitcnt = 0;   // discard the remaining bits of the current byte

  int c;
  unsigned hdr[4];   // LEN (little endian) followed by its one's complement
  for (int i = 0; i < 4; i++) {
    if ((c = s->in(s->ctx)) < 0) return INFLATE_ERR_INPUT;
    hdr[i] = c & 0xff;
  }
  s->in_bytes += 4;
  unsigned len = hdr[0] | (hdr[1] << 8);
  unsigned nlen = hdr[2] | (hdr[3] << 8);
  if (len != (~nlen & 0xffff)) return INFLATE_ERR_DATA;

  while (len--) {
    if ((c = s->in(s->ctx)) < 0) return INFLATE_ERR_INPUT;
    s->in_bytes++;
    if (!put(s, (uint8_t) c)) return s->error;
  }
  return INFLATE_OK;
}

static int fixed(State *s) {
  static short lencnt[MAXBITS + 1], lensym[FIXLCODES];
  static short distcnt[MAXBITS + 1], distsym[MAXDCODES];
  static bool built = false;
  Huffman lencode = { lencnt, lensym };
  Huffman distcode = { distcnt, distsym };

  if (!built) {
    short lengths[FIXLCODES];
    int symbol = 0;
    for (; symbol < 144; symbol++) lengths[symbol] = 8;
    for (; symbol < 256; symbol++) lengths[symbol] = 9;
    for (; symbol < 280; symbol++) lengths[symbol] = 7;
    for (; symbol < FIXLCODES; symbol++) lengths[symbol] = 8;
    construct(&lencode, lengths, FIXLCODES);
    for (symbol = 0; symbol < MAXDCODES; symbol++) lengths[symbol] = 5;
    construct(&distcode, lengths, MAXDCODES);
    built = true;
  }
  return codes(s, &lencode, &distcode);
}

static int dynamic(State *s) {
  static const short order[19] = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };
  short lengths[MAXCODES];
  short lencnt[MAXBITS + 1], lensym[MAXLCODES];
  short distcnt[MAXBITS + 1], distsym[MAXDCODES];
  Huffman lencode = { lencnt, lensym };
  Huffman distcode = { distcnt, distsym };

  int nlen = bits(s, 5) + 257;
  int ndist = bits(s, 5) + 1;
  int ncode = bits(s, 4) + 4;
  if (s->error) return s->error;
  if (nlen > MAXLCODES || ndist > MAXDCODES) return INFLATE_ERR_DATA;

  int index = 0;
  for (; index < ncode; index++) lengths[order[index]] = bits(s, 3);
  for (; index < 19; index++) lengths[order[index]] = 0;
  if (s->error) return s->error;

  int err = construct(&lencode, lengths, 19);
  if (err != 0) return INFLATE_ERR_DATA;   // the code length code must be complete

  index = 0;
  while (index < nlen + ndist) {
    int symbol = decode(s, &lencode);
    if (s->error) return s->error;
    if (symbol < 0) return INFLATE_ERR_DATA;
    if (symbol < 16) {
      lengths[index++] = symbol;
    } else {
      int len = 0, count;
      if (symbol == 16) {
        if (index == 0) return INFLATE_ERR_DATA;   // no previous length to repeat
        len = lengths[index - 1];
        count = 3 + bits(s, 2);
      } else if (symbol == 17) {
        count = 3 + bits(s, 3);
      } else {
        count = 11 + bits(s, 7);
      }
      if (s->error) return s->error;
      if (index + count > nlen + ndist) return INFLATE_ERR_DATA;
      while (count--) lengths[index++] = len;
    }
  }

  if (lengths[256] == 0) return INFLATE_ERR_DATA;   // no end-of-block code

  err = construct(&lencode, lengths, nlen);
  if (err && (err < 0 || nlen != lencode.count[0] + lencode.count[1])) return INFLATE_ERR_DATA;

  err = construct(&distcode, lengths + nlen, ndist);
  if (err && (err < 0 || ndist != distcode.count[0] + distcode.count[1])) return INFLATE_ERR_DATA;

  return codes(s, &lencode, &distcode);
}

// ---------------------------------------------------------------- api

int inflate_stream(inflate_in_cb in, inflate_out_cb out, void *ctx,
                   uint8_t *window, InflateStats *stats) {
  State s;
  if (window == 0) return INFLATE_ERR_WINDOW;
  s.in = in;
  s.out = out;
  s.ctx = ctx;
  s.window = window;
  s.wpos = 0;
  s.flushed = 0;
  s.in_bytes = 0;
  s.bitbuf = 0;
  s.bitcnt = 0;
  s.error = 0;

  int err, last;
  do {
    last = bits(&s, 1);
    int type = bits(&s, 2);
    if (s.error) { err = s.error; break; }
    switch (type) {
      case 0:  err = stored(&s); break;
      case 1:  err = fixed(&s); break;
      case 2:  err = dynamic(&s); break;
      default: err = INFLATE_ERR_DATA;
    }
    if (err == INFLATE_OK && s.error) err = s.error;
  } while (!last && err == INFLATE_OK);

  if (err == INFLATE_OK && !flush(&s)) err = s.error;

  if (stats) {
    stats->in_bytes = s.in_bytes;
    stats->out_bytes = s.wpos;
  }
  return err;
}

uint32_t crc32_update(uint32_t crc, const uint8_t *data, size_t len) {
  // Nibble driven CRC-32 (polynomial 0xEDB88320), small table, no setup
  static const uint32_t table[16] = {
    0x00000000, 0x1DB71064, 0x3B6E20C8, 0x26D930AC, 0x76DC4190, 0x6B6B51F4, 0x4DB26158, 0x5005713C,
    0xEDB88320, 0xF00F9344, 0xD6D6A3E8, 0xCB61B38C, 0x9B64C2B0, 0x86D3D2D4, 0xA00AE278, 0xBDBDF21C };
  crc = ~crc;
  while (len--) {
    crc ^= *data++;
    crc = table[crc & 15] ^ (crc >> 4);
    crc = table[crc & 15] ^ (crc >> 4);
  }
  return ~crc;
}
