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

// PC test for Nifi/inflate.cpp: inflates every entry of a zip file and checks
// the CRC-32 and size stored in the zip headers.
//
// Build (any C++ compiler):
//   g++ -O2 -Wall -o inflate_test tester/inflate_test.cpp Nifi/inflate.cpp
// Run:
//   inflate_test some.zip [other.zip ...]
//
// Only the local file headers are used (same code path as the firmware), so
// entries with a data descriptor (flag bit 3) are also exercised.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../Nifi/inflate.h"

struct Ctx {
  FILE *f;
  long limit;        // remaining compressed bytes, -1 when unknown
  uint32_t crc;
  uint32_t size;
};

static int in_cb(void *p) {
  Ctx *c = (Ctx *) p;
  if (c->limit == 0) return -1;
  int ch = fgetc(c->f);
  if (ch == EOF) return -1;
  if (c->limit > 0) c->limit--;
  return ch;
}

static bool out_cb(void *p, const uint8_t *data, size_t len) {
  Ctx *c = (Ctx *) p;
  c->crc = crc32_update(c->crc, data, len);
  c->size += len;
  return true;
}

static uint32_t rd16(const uint8_t *p) { return p[0] | (p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return rd16(p) | (rd16(p + 2) << 16); }

static int test_zip(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) { printf("%s: cannot open\n", path); return 1; }
  int failures = 0;
  uint8_t h[30];
  while (fread(h, 1, 30, f) == 30) {
    if (rd32(h) != 0x04034b50) break;   // central directory reached
    unsigned flags = rd16(h + 6), method = rd16(h + 8);
    uint32_t crc = rd32(h + 14), csize = rd32(h + 18), usize = rd32(h + 22);
    unsigned nlen = rd16(h + 26), xlen = rd16(h + 28);
    char name[512];
    if (nlen >= sizeof(name)) nlen = sizeof(name) - 1;
    fread(name, 1, nlen, f); name[nlen] = 0;
    fseek(f, rd16(h + 26) - nlen + xlen, SEEK_CUR);
    long data = ftell(f);

    Ctx c = { f, (flags & 8) ? -1L : (long) csize, 0, 0 };
    InflateStats st = { 0, 0 };
    int err = 0;
    if (method == 8) {
      uint8_t *window = (uint8_t *) malloc(INFLATE_WINDOW_SIZE);
      err = inflate_stream(in_cb, out_cb, &c, window, &st);
      free(window);
    } else if (method == 0) {
      uint8_t buf[4096];
      uint32_t left = usize;
      while (left) {
        size_t n = fread(buf, 1, left > sizeof(buf) ? sizeof(buf) : left, f);
        if (!n) break;
        out_cb(&c, buf, n);
        left -= n;
      }
      st.in_bytes = usize; st.out_bytes = c.size;
    } else {
      printf("  %s: method %u not supported, skipped\n", name, method);
      fseek(f, data + csize, SEEK_SET);
      continue;
    }

    fseek(f, data + st.in_bytes, SEEK_SET);
    if (flags & 8) {
      uint8_t d[16];
      fread(d, 1, 4, f);
      if (rd32(d) == 0x08074b50) fread(d, 1, 4, f);
      crc = rd32(d);
      fread(d, 1, 8, f);
      csize = rd32(d); usize = rd32(d + 4);
    }

    bool ok = err == 0 && c.crc == crc && c.size == usize && st.in_bytes == csize;
    printf("  %-60.60s %8u bytes  %s", name, c.size, ok ? "OK" : "FAIL");
    if (!ok) printf(" (err %d, crc %08X/%08X, size %u/%u, in %u/%u)", err, c.crc, crc, c.size, usize, st.in_bytes, csize);
    printf("\n");
    if (!ok) failures++;
  }
  fclose(f);
  return failures;
}

int main(int argc, char **argv) {
  if (argc < 2) { printf("usage: inflate_test file.zip ...\n"); return 2; }
  int failures = 0;
  for (int i = 1; i < argc; i++) {
    printf("%s\n", argv[i]);
    failures += test_zip(argv[i]);
  }
  printf(failures ? "%d FAILURES\n" : "all entries OK\n", failures);
  return failures ? 1 : 0;
}
