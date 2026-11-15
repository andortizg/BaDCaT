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

// ROM loader for the NETROM utility: browse HTTP directory listings, download
// a file (zip entries are extracted) to the ESP flash file system and serve it
// to the MSX in blocks.
//
// Everything heavy happens on the ESP: TLS, redirects, chunked transfers, HTML
// listing parsing and DEFLATE. The transfer works in two phases so that the
// TLS buffers and the 32 KB inflate window never have to coexist in the small
// ESP8266 heap: the compressed file is first stored in flash, the connection
// is closed, and only then the zip entry is inflated (flash to flash).
#include "romloader.h"
#include "exchange.h"
#include "protocol.h"
#include "configuration.h"
#include "connection_manager.h"
#include "inflate.h"
#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecureBearSSL.h>
#include <LittleFS.h>
#include <ESP8266httpUpdate.h>
#include <Updater.h>
#include <ctype.h>
#include <strings.h>

#define LIST_FILE   "/list.bin"
#define DL_FILE     "/download.bin"
#define ROM_FILE    "/rom.bin"

#define MAX_REDIRECTS 5
#define FS_MARGIN     8192      // flash bytes kept free
#define LIST_NAME_MAX 79
#define LIST_HREF_MAX 255
#define LIST_PAGE_MAX 32
#define FILTER_MAX    40

static String current_url;       // location of the current listing ("" = none)
static uint32_t list_count = 0;  // entries in LIST_FILE

static bool rom_ready = false;
static uint32_t rom_size = 0;
static uint32_t rom_crc = 0;
static char rom_name[LIST_NAME_MAX + 1];
static File rom_file;

// --------------------------------------------------------------------------
// Small helpers
// --------------------------------------------------------------------------

static uint32_t get_dword() {
  uint32_t v = get_word();
  return v | ((uint32_t) get_word() << 16);
}

static void publish_dword(uint32_t v) {
  publish_word(v & 0xffff);
  publish_word(v >> 16);
}

static bool starts_with_ci(const String& s, const char *prefix) {
  size_t n = strlen(prefix);
  if (s.length() < n) return false;
  for (size_t i = 0; i < n; i++)
    if (tolower(s[i]) != tolower(prefix[i])) return false;
  return true;
}

static bool is_http_url(const String& url) {
  return starts_with_ci(url, "http://") || starts_with_ci(url, "https://");
}

// "https://host:port" part of an URL (no trailing slash)
static String url_origin(const String& url) {
  int p = url.indexOf("://");
  if (p < 0) return "";
  int slash = url.indexOf('/', p + 3);
  return slash < 0 ? url : url.substring(0, slash);
}

// Host name of an URL, lower case, without the port
static String url_host(const String& url) {
  String o = url_origin(url);
  int p = o.indexOf("://");
  if (p < 0) return "";
  o = o.substring(p + 3);
  int colon = o.indexOf(':');
  if (colon >= 0) o = o.substring(0, colon);
  o.toLowerCase();
  return o;
}

// Resolves a (possibly relative) link against a base URL
static String resolve_url(const String& base, String href) {
  href.trim();
  if (is_http_url(href)) return href;
  if (href.startsWith("//")) {
    int p = base.indexOf("://");
    return (p < 0 ? String("https:") : base.substring(0, p + 1)) + href;
  }
  if (href.startsWith("/")) return url_origin(base) + href;

  int p = base.indexOf("://");
  int cut = base.lastIndexOf('/');
  if (p < 0 || cut < p + 3) return url_origin(base) + "/" + href;
  return base.substring(0, cut + 1) + href;
}

// Spaces typed by the user become %20 (the rest is sent as is)
static String encode_spaces(const char *s) {
  String r;
  r.reserve(strlen(s) + 8);
  for (; *s; s++) {
    if (*s == ' ') r += "%20"; else r += *s;
  }
  return r;
}

static int hexval(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

// Copies src into dst (max bytes including the terminator), decoding %XX and
// replacing non ASCII characters with '?'
static void url_decode_ascii(char *dst, const char *src, size_t max) {
  size_t o = 0;
  while (*src && o < max - 1) {
    unsigned char c = *src++;
    if (c == '%' && hexval(src[0]) >= 0 && hexval(src[1]) >= 0) {
      c = hexval(src[0]) * 16 + hexval(src[1]);
      src += 2;
    } else if (c == '+') {
      c = ' ';
    }
    if (c >= 0x80 && c < 0xC0) continue;   // UTF-8 continuation byte
    if (c >= 0xC0 || c < 0x20) c = '?';
    dst[o++] = c;
  }
  dst[o] = 0;
}

// Last path segment of an URL, decoded (used as file name for direct downloads)
static void url_basename(char *dst, const String& url, size_t max) {
  String u = url;
  int q = u.indexOf('?');
  if (q >= 0) u = u.substring(0, q);
  while (u.endsWith("/")) u.remove(u.length() - 1);
  int cut = u.lastIndexOf('/');
  if (cut >= 0) u = u.substring(cut + 1);
  url_decode_ascii(dst, u.c_str(), max);
  if (dst[0] == 0) strncpy(dst, "download", max);
}

static void publish_http_error(unsigned char code, unsigned int status) {
  publish_byte(code);
  if (code == ERR_HTTP) publish_word(status);
}

// --------------------------------------------------------------------------
// HTTP fetch with manual redirects (the scheme may change between hops)
// --------------------------------------------------------------------------

enum FetchResult {
  FETCH_OK = 0,
  FETCH_INVALID_URL,
  FETCH_CONNECT,       // could not connect / no answer
  FETCH_HTTP,          // HTTP status other than 200 (in status)
  FETCH_TOO_LARGE,     // Content-Length above max_size
  FETCH_TRANSFER,      // the body transfer failed
  FETCH_REDIRECT       // too many redirects
};

static int fetch(String url, Stream& sink, uint32_t max_size, int& status) {
  status = 0;
  for (int hop = 0; hop <= MAX_REDIRECTS; hop++) {
    bool https;
    if (starts_with_ci(url, "https://")) https = true;
    else if (starts_with_ci(url, "http://")) https = false;
    else return FETCH_INVALID_URL;

    WiFiClient *client;
    if (https) {
      BearSSL::WiFiClientSecure *c = new BearSSL::WiFiClientSecure();
      c->setInsecure();   // no RTC / trust store on the modem: integrity comes from the zip CRC
      client = c;
    } else {
      client = new WiFiClient();
    }
    client->setTimeout(HTTP_TIMEOUT);

    int outcome = -1;   // -1 = follow the redirect in url
    {
      // The HTTPClient must die before the client it points to
      HTTPClient http;
      http.setTimeout(HTTP_TIMEOUT);
      http.setUserAgent(HTTP_USER_AGENT);
      http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
      http.setReuse(false);
      static const char *keys[] = { "Location" };
      http.collectHeaders(keys, 1);

      if (!http.begin(*client, url)) {
        outcome = FETCH_INVALID_URL;
      } else {
        int code = http.GET();
        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
          String location = http.header("Location");
          if (location.length() == 0) { status = code; outcome = FETCH_HTTP; }
          else url = resolve_url(url, location);
        } else if (code <= 0) {
          outcome = FETCH_CONNECT;
        } else if (code != 200) {
          status = code;
          outcome = FETCH_HTTP;
        } else {
          int length = http.getSize();
          if (length > 0 && (uint32_t) length > max_size) {
            outcome = FETCH_TOO_LARGE;
          } else {
            int written = http.writeToStream(&sink);
            outcome = written < 0 ? FETCH_TRANSFER : FETCH_OK;
          }
        }
        http.end();
      }
    }
    delete client;
    if (outcome >= 0) return outcome;
  }
  return FETCH_REDIRECT;
}

// Maps a fetch result to a protocol error code (+ HTTP status for ERR_HTTP)
static unsigned char fetch_error(int result, int status, unsigned int& out_status) {
  out_status = 0;
  switch (result) {
    case FETCH_OK:          return ERR_OK;
    case FETCH_INVALID_URL: return ERR_INV_PARAM;
    case FETCH_CONNECT:     return ERR_HTTP;                     // status 0
    case FETCH_HTTP:        out_status = status; return ERR_HTTP;
    case FETCH_TOO_LARGE:   return ERR_LARGE_DGRAM;
    case FETCH_TRANSFER:    out_status = 1; return ERR_HTTP;
    default:                out_status = 2; return ERR_HTTP;    // redirect loop
  }
}

// --------------------------------------------------------------------------
// Sinks
// --------------------------------------------------------------------------

// Base for write-only sinks used with HTTPClient::writeToStream
class SinkStream : public Stream {
public:
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  void flush() override {}
};

// Writes to a flash file up to a maximum size; refuses further data after it
class CappedFile : public SinkStream {
public:
  File file;
  uint32_t cap;
  uint32_t written = 0;
  bool overflow = false;
  bool fs_error = false;

  CappedFile(File f, uint32_t limit) : file(f), cap(limit) {}

  size_t write(uint8_t b) override { return write(&b, 1); }

  size_t write(const uint8_t *data, size_t len) override {
    if (written + len > cap) { overflow = true; return 0; }
    size_t n = file.write(data, len);
    if (n != len) { fs_error = true; return 0; }
    written += n;
    yield();
    return n;
  }
};

// Streaming parser for HTML directory listings. Every link becomes an entry:
//   flags (1 byte: bit 0 = directory), size (4 bytes), href (zero terminated),
//   display name (zero terminated, ASCII)
// The size is the last size-looking token in the text that follows the link
// in the same row (works with file-hunter, archive.org listings and the
// archive.org zip content viewer).
class ListingParser : public SinkStream {
public:
  File out;
  String host;          // links to other hosts are ignored
  uint32_t count = 0;

  ListingParser() { tag[0] = 0; }

  size_t write(uint8_t b) override { feed(b); return 1; }

  size_t write(const uint8_t *data, size_t len) override {
    for (size_t i = 0; i < len; i++) feed(data[i]);
    yield();
    return len;
  }

  // Call once the whole document was fed
  void finish() {
    if (in_tag) { in_tag = false; }
    else handle_text();
    finalize_pending();
  }

private:
  static const int TAG_MAX  = 400;
  static const int TEXT_MAX = 120;
  static const int NAME_MAX = 120;

  bool in_tag = false;
  char tag[TAG_MAX + 1];
  int taglen = 0;
  char text[TEXT_MAX + 1];
  int textlen = 0;

  bool in_anchor = false;
  char anchor_href[LIST_HREF_MAX + 1];
  char anchor_name[NAME_MAX + 1];
  int anchor_namelen = 0;

  bool pending = false;       // an entry is waiting for its size / row end
  char pend_href[LIST_HREF_MAX + 1];
  char pend_name[LIST_NAME_MAX + 1];
  uint32_t pend_size = 0;

  void feed(unsigned char c) {
    if (in_tag) {
      if (c == '>') {
        tag[taglen] = 0;
        in_tag = false;
        handle_tag();
      } else if (taglen < TAG_MAX) {
        tag[taglen++] = c;
      }
    } else if (c == '<') {
      handle_text();
      textlen = 0;
      in_tag = true;
      taglen = 0;
    } else if (textlen < TEXT_MAX) {
      if (c == '\n' || c == '\r' || c == '\t') c = ' ';
      text[textlen++] = c;
    }
  }

  // Text between two tags
  void handle_text() {
    text[textlen] = 0;
    if (in_anchor) {
      for (int i = 0; i < textlen && anchor_namelen < NAME_MAX; i++)
        anchor_name[anchor_namelen++] = text[i];
    } else if (pending) {
      uint32_t size;
      if (find_size(text, size)) pend_size = size;
    }
  }

  void handle_tag() {
    // Tag name
    int i = 0;
    while (tag[i] == ' ') i++;
    bool closing = tag[i] == '/';
    if (closing) i++;
    char name[4];
    int n = 0;
    while (tag[i] && tag[i] != ' ' && tag[i] != '\t' && tag[i] != '\n' && tag[i] != '\r' && tag[i] != '/' && n < 3)
      name[n++] = tolower(tag[i++]);
    name[n] = 0;
    bool at_end = tag[i] == 0 || tag[i] == ' ' || tag[i] == '\t' || tag[i] == '\n' || tag[i] == '\r' || tag[i] == '/';
    if (!at_end) return;

    if (strcmp(name, "a") == 0) {
      if (closing) { end_anchor(); return; }
      char href[LIST_HREF_MAX + 1];
      if (!get_href(tag + i, href)) return;
      if (!acceptable(href)) return;
      finalize_pending();
      strcpy(anchor_href, href);
      anchor_namelen = 0;
      in_anchor = true;
    } else if (strcmp(name, "tr") == 0) {
      if (in_anchor) end_anchor();
      finalize_pending();
    }
  }

  // Extracts the href attribute value
  bool get_href(const char *attrs, char *href) {
    const char *p = attrs;
    while (*p) {
      if (tolower(p[0]) == 'h' && tolower(p[1]) == 'r' && tolower(p[2]) == 'e' && tolower(p[3]) == 'f' &&
          (p == attrs || p[-1] == ' ' || p[-1] == '\t' || p[-1] == '\n')) {
        p += 4;
        while (*p == ' ') p++;
        if (*p != '=') return false;
        p++;
        while (*p == ' ') p++;
        char quote = 0;
        if (*p == '"' || *p == '\'') quote = *p++;
        int o = 0;
        while (*p && o < LIST_HREF_MAX) {
          if (quote ? *p == quote : (*p == ' ' || *p == '>')) break;
          href[o++] = *p++;
        }
        href[o] = 0;
        return o > 0;
      }
      p++;
    }
    return false;
  }

  bool acceptable(const char *href) {
    if (href[0] == 0 || href[0] == '#' || href[0] == '?') return false;
    if (strchr(href, '?')) return false;                       // sort links, viewers, ...
    if (strncasecmp(href, "mailto:", 7) == 0 || strncasecmp(href, "javascript:", 11) == 0) return false;
    if (strcmp(href, "/") == 0 || strcmp(href, "./") == 0 || strcmp(href, ".") == 0) return false;
    if (strcmp(href, "../") == 0 || strcmp(href, "..") == 0) return false;
    size_t len = strlen(href);
    if (len >= 4 && strcmp(href + len - 4, "/../") == 0) return false;
    if (strncasecmp(href, "http://", 7) == 0 || strncasecmp(href, "https://", 8) == 0) {
      String h = url_host(String(href));
      if (h != host) return false;
    }
    return true;
  }

  void end_anchor() {
    if (!in_anchor) return;
    in_anchor = false;
    anchor_name[anchor_namelen] = 0;

    // Display name: the link text, or the last path segment of the link
    char name[LIST_NAME_MAX + 1];
    decode_entities(name, anchor_name, sizeof(name));
    trim(name);
    bool dir = anchor_href[strlen(anchor_href) - 1] == '/';
    if (name[0] == 0) {
      String h = anchor_href;
      while (h.endsWith("/")) h.remove(h.length() - 1);
      int cut = h.lastIndexOf('/');
      if (cut >= 0) h = h.substring(cut + 1);
      url_decode_ascii(name, h.c_str(), sizeof(name));
    }
    size_t nl = strlen(name);
    if (dir && nl > 1 && name[nl - 1] == '/') name[nl - 1] = 0;
    if (name[0] == 0) return;

    strcpy(pend_href, anchor_href);
    strcpy(pend_name, name);
    pend_size = 0;
    pending = true;
  }

  void finalize_pending() {
    if (!pending) return;
    pending = false;
    bool dir = pend_href[strlen(pend_href) - 1] == '/';
    uint8_t flags = dir ? 1 : 0;
    uint32_t size = dir ? 0 : pend_size;
    out.write(&flags, 1);
    out.write((const uint8_t *) &size, 4);
    out.write((const uint8_t *) pend_href, strlen(pend_href) + 1);
    out.write((const uint8_t *) pend_name, strlen(pend_name) + 1);
    count++;
  }

  // Last token like "16384", "17.76 KB", "26.5M" in the text, ignoring numbers
  // that are part of dates and times
  static bool find_size(const char *s, uint32_t& result) {
    bool found = false;
    for (int i = 0; s[i]; i++) {
      if (!isdigit((unsigned char) s[i])) continue;
      if (i > 0) {
        char p = s[i - 1];
        if (isdigit((unsigned char) p) || p == '.' || p == ':' || p == '-' || p == '/') {
          while (isdigit((unsigned char) s[i])) i++;
          i--;
          continue;
        }
      }
      uint32_t whole = 0;
      int j = i;
      while (isdigit((unsigned char) s[j])) { whole = whole * 10 + (s[j] - '0'); j++; }
      uint32_t frac = 0, fdiv = 1;
      if (s[j] == '.' && isdigit((unsigned char) s[j + 1])) {
        j++;
        while (isdigit((unsigned char) s[j])) { if (fdiv < 1000) { frac = frac * 10 + (s[j] - '0'); fdiv *= 10; } j++; }
      }
      int k = j;
      if (s[k] == ' ') k++;
      uint32_t mult = 1;
      char u = tolower(s[k]);
      if (u == 'k') mult = 1024u;
      else if (u == 'm') mult = 1024u * 1024u;
      else if (u == 'g') mult = 1024u * 1024u * 1024u;
      if (mult > 1) {
        k++;
        if (tolower(s[k]) == 'i') k++;
        if (tolower(s[k]) == 'b') k++;
      } else if (u == 'b') {
        k++;
      } else {
        k = j;
      }
      char after = s[k];
      if (isdigit((unsigned char) after) || after == ':' || after == '-' || after == '/' || after == '.' || isalpha((unsigned char) after)) {
        i = j - 1;
        continue;
      }
      result = whole * mult + (uint32_t) ((uint64_t) frac * mult / fdiv);
      found = true;
      i = k - 1;
    }
    return found;
  }

  static void decode_entities(char *dst, const char *src, size_t max) {
    size_t o = 0;
    while (*src && o < max - 1) {
      unsigned char c = *src++;
      if (c == '&') {
        const char *semi = strchr(src, ';');
        if (semi && semi - src <= 8) {
          char ent[10];
          size_t n = semi - src;
          memcpy(ent, src, n);
          ent[n] = 0;
          src = semi + 1;
          if (strcmp(ent, "amp") == 0) c = '&';
          else if (strcmp(ent, "lt") == 0) c = '<';
          else if (strcmp(ent, "gt") == 0) c = '>';
          else if (strcmp(ent, "quot") == 0) c = '"';
          else if (strcmp(ent, "apos") == 0 || strcmp(ent, "#39") == 0) c = '\'';
          else if (strcmp(ent, "nbsp") == 0) c = ' ';
          else if (ent[0] == '#') { long v = atol(ent + 1); c = (v >= 32 && v < 127) ? v : '?'; }
          else c = '?';
        }
      }
      if (c >= 0x80 && c < 0xC0) continue;   // UTF-8 continuation byte
      if (c >= 0xC0 || c < 0x20) c = '?';
      dst[o++] = c;
    }
    dst[o] = 0;
  }

  static void trim(char *s) {
    size_t len = strlen(s);
    while (len && s[len - 1] == ' ') s[--len] = 0;
    size_t i = 0;
    while (s[i] == ' ') i++;
    if (i) memmove(s, s + i, len - i + 1);
  }
};

// --------------------------------------------------------------------------
// Listing storage
// --------------------------------------------------------------------------

struct ListRecord {
  uint8_t flags;
  uint32_t size;
  char href[LIST_HREF_MAX + 1];
  char name[LIST_NAME_MAX + 1];
};

static bool read_zstring(File& f, char *dst, size_t max) {
  size_t o = 0;
  for (;;) {
    int c = f.read();
    if (c < 0) return false;
    if (c == 0) break;
    if (o < max - 1) dst[o++] = c;
  }
  dst[o] = 0;
  return true;
}

static bool read_record(File& f, ListRecord& r) {
  if (f.read(&r.flags, 1) != 1) return false;
  if (f.read((uint8_t *) &r.size, 4) != 4) return false;
  if (!read_zstring(f, r.href, sizeof(r.href))) return false;
  return read_zstring(f, r.name, sizeof(r.name));
}

static bool find_record(uint32_t index, ListRecord& r) {
  if (index >= list_count) return false;
  File f = LittleFS.open(LIST_FILE, "r");
  if (!f) return false;
  bool ok = false;
  for (uint32_t i = 0; i <= index; i++) {
    ok = read_record(f, r);
    if (!ok) break;
  }
  f.close();
  return ok;
}

// Fetches and parses the listing of url. Returns a protocol error code.
static unsigned char do_list(const String& url, unsigned int& http_status) {
  http_status = 0;
  if (WiFi.status() != WL_CONNECTED) return ERR_NO_NETWORK;

  ListingParser parser;
  parser.out = LittleFS.open(LIST_FILE, "w");
  if (!parser.out) return ERR_STORAGE;
  parser.host = url_host(url);

  int status;
  int result = fetch(url, parser, 0xFFFFFFFFu, status);
  parser.finish();
  parser.out.close();

  unsigned char err = fetch_error(result, status, http_status);
  if (err != ERR_OK) {
    list_count = 0;
    return err;
  }
  list_count = parser.count;
  current_url = url;
  return ERR_OK;
}

// --------------------------------------------------------------------------
// Download and zip extraction
// --------------------------------------------------------------------------

struct ZipEntry {
  uint32_t data;      // offset of the compressed data in the zip
  uint32_t csize, usize, crc;
  uint16_t flags, method;
  char name[LIST_NAME_MAX + 1];
  bool valid;
};

struct ZipCtx {
  File *in;
  int32_t limit;          // compressed bytes left, -1 = unknown (data descriptor)
  uint8_t buf[256];
  int pos, len;
  File *out;              // 0 = discard
  uint32_t cap;
  uint32_t size;
  uint32_t crc;
  bool overflow;
  bool fs_error;
};

static int zip_in(void *p) {
  ZipCtx *c = (ZipCtx *) p;
  if (c->pos >= c->len) {
    if (c->limit == 0) return -1;
    size_t want = sizeof(c->buf);
    if (c->limit > 0 && (uint32_t) c->limit < want) want = c->limit;
    c->len = c->in->read(c->buf, want);
    c->pos = 0;
    if (c->len <= 0) { c->len = 0; return -1; }
    if (c->limit > 0) c->limit -= c->len;
    yield();
  }
  return c->buf[c->pos++];
}

static bool zip_out(void *p, const uint8_t *data, size_t len) {
  ZipCtx *c = (ZipCtx *) p;
  if (c->out) {
    if (c->size + len > c->cap) { c->overflow = true; return false; }
    if (c->out->write(data, len) != len) { c->fs_error = true; return false; }
  }
  c->crc = crc32_update(c->crc, data, len);
  c->size += len;
  yield();
  return true;
}

static uint32_t rd16(const uint8_t *p) { return p[0] | (p[1] << 8); }
static uint32_t rd32(const uint8_t *p) { return rd16(p) | (rd16(p + 2) << 16); }

static bool rom_like_name(const char *name) {
  const char *dot = strrchr(name, '.');
  if (!dot) return false;
  return strcasecmp(dot, ".rom") == 0 || strcasecmp(dot, ".mx1") == 0 || strcasecmp(dot, ".mx2") == 0 ||
         strcasecmp(dot, ".bin") == 0 || strcasecmp(dot, ".sg") == 0 || strcasecmp(dot, ".col") == 0;
}

// Inflates (or copies) one entry. out = 0 discards the data (used to skip
// entries whose compressed size is unknown). Returns a protocol error code and
// updates e.data + consumed in *consumed.
static unsigned char zip_extract(File& z, ZipEntry& e, File *out, uint32_t cap, uint32_t *consumed) {
  ZipCtx ctx;
  ctx.in = &z;
  ctx.limit = (e.flags & 8) ? -1 : (int32_t) e.csize;
  ctx.pos = ctx.len = 0;
  ctx.out = out;
  ctx.cap = cap;
  ctx.size = 0;
  ctx.crc = 0;
  ctx.overflow = false;
  ctx.fs_error = false;

  if (!z.seek(e.data, SeekSet)) return ERR_BAD_ARCHIVE;

  if (e.method == 0) {
    if (e.flags & 8) return ERR_BAD_ARCHIVE;   // stored entry with unknown size
    uint32_t left = e.usize;
    while (left) {
      uint8_t buf[256];
      size_t n = z.read(buf, left > sizeof(buf) ? sizeof(buf) : left);
      if (n == 0) return ERR_BAD_ARCHIVE;
      if (!zip_out(&ctx, buf, n)) break;
      left -= n;
    }
    *consumed = e.usize;
  } else if (e.method == 8) {
    uint8_t *window = (uint8_t *) malloc(INFLATE_WINDOW_SIZE);
    if (!window) return ERR_BUFFER;
    InflateStats st = { 0, 0 };
    int res = inflate_stream(zip_in, zip_out, &ctx, window, &st);
    free(window);
    *consumed = st.in_bytes;
    if (ctx.overflow) return ERR_LARGE_DGRAM;
    if (ctx.fs_error) return ERR_STORAGE;
    if (res != INFLATE_OK) return ERR_BAD_ARCHIVE;

    if (e.flags & 8) {
      // Data descriptor: [signature] crc, compressed size, uncompressed size
      uint8_t d[16];
      if (!z.seek(e.data + st.in_bytes, SeekSet) || z.read(d, 4) != 4) return ERR_BAD_ARCHIVE;
      if (rd32(d) == 0x08074b50) { if (z.read(d, 4) != 4) return ERR_BAD_ARCHIVE; }
      e.crc = rd32(d);
      if (z.read(d, 8) != 8) return ERR_BAD_ARCHIVE;
      e.csize = rd32(d);
      e.usize = rd32(d + 4);
    }
  } else {
    return ERR_BAD_ARCHIVE;   // unsupported compression method
  }

  if (ctx.overflow) return ERR_LARGE_DGRAM;
  if (ctx.fs_error) return ERR_STORAGE;
  if (out) {
    if (ctx.size != e.usize || ctx.crc != e.crc) return ERR_BAD_ARCHIVE;
    rom_size = ctx.size;
    rom_crc = ctx.crc;
  }
  return ERR_OK;
}

// Walks the local headers of the zip, picks the first ROM-looking entry (or
// the first file when none has a known extension) and extracts it to ROM_FILE.
static unsigned char unzip_first_rom(File& z, uint32_t cap) {
  ZipEntry fallback;
  fallback.valid = false;
  uint32_t pos = 0;

  for (;;) {
    uint8_t h[30];
    if (!z.seek(pos, SeekSet) || z.read(h, 30) != 30) break;
    if (rd32(h) != 0x04034b50) break;   // central directory: no more entries

    ZipEntry e;
    e.flags = rd16(h + 6);
    e.method = rd16(h + 8);
    e.crc = rd32(h + 14);
    e.csize = rd32(h + 18);
    e.usize = rd32(h + 22);
    unsigned nlen = rd16(h + 26), xlen = rd16(h + 28);
    char full[256];
    unsigned take = nlen < sizeof(full) - 1 ? nlen : sizeof(full) - 1;
    if (z.read((uint8_t *) full, take) != take) break;
    full[take] = 0;
    e.data = pos + 30 + nlen + xlen;
    e.valid = true;

    const char *base = strrchr(full, '/');
    base = base ? base + 1 : full;
    url_decode_ascii(e.name, base, sizeof(e.name));
    bool is_dir = nlen > 0 && full[take - 1] == '/';
    bool is_file = !is_dir && (e.usize > 0 || (e.flags & 8));

    if (is_file && rom_like_name(e.name)) {
      File out = LittleFS.open(ROM_FILE, "w");
      if (!out) return ERR_STORAGE;
      uint32_t consumed;
      unsigned char err = zip_extract(z, e, &out, cap, &consumed);
      out.close();
      if (err == ERR_OK) strcpy(rom_name, e.name);
      return err;
    }
    if (is_file && !fallback.valid) fallback = e;

    // Skip to the next local header
    if (!(e.flags & 8)) {
      pos = e.data + e.csize;
    } else {
      uint32_t consumed;
      unsigned char err = zip_extract(z, e, 0, cap, &consumed);
      if (err != ERR_OK) return err;
      pos = e.data + consumed;
      uint8_t d[4];
      if (!z.seek(pos, SeekSet) || z.read(d, 4) != 4) return ERR_BAD_ARCHIVE;
      pos += rd32(d) == 0x08074b50 ? 16 : 12;
    }
  }

  if (!fallback.valid) return ERR_BAD_ARCHIVE;
  File out = LittleFS.open(ROM_FILE, "w");
  if (!out) return ERR_STORAGE;
  uint32_t consumed;
  unsigned char err = zip_extract(z, fallback, &out, cap, &consumed);
  out.close();
  if (err == ERR_OK) strcpy(rom_name, fallback.name);
  return err;
}

static uint32_t flash_capacity() {
  FSInfo info;
  if (!LittleFS.info(info)) return 0;
  uint32_t free_bytes = info.totalBytes > info.usedBytes ? info.totalBytes - info.usedBytes : 0;
  uint32_t cap = free_bytes > FS_MARGIN ? free_bytes - FS_MARGIN : 0;
  if (cap > MAX_ROM_DOWNLOAD) cap = MAX_ROM_DOWNLOAD;
  return cap;
}

static void discard_rom() {
  rom_ready = false;
  if (rom_file) rom_file.close();
  LittleFS.remove(ROM_FILE);
  LittleFS.remove(DL_FILE);
}

// Downloads url to flash, extracts it when it is a zip and publishes the
// response of the download commands.
static void do_download(const String& url, const char *display_name) {
  unsigned int http_status = 0;
  discard_rom();

  if (WiFi.status() != WL_CONNECTED) { publish_byte(ERR_NO_NETWORK); return; }

  uint32_t cap = flash_capacity();
  if (cap == 0) { publish_byte(ERR_STORAGE); return; }

  File dl = LittleFS.open(DL_FILE, "w");
  if (!dl) { publish_byte(ERR_STORAGE); return; }
  CappedFile sink(dl, cap);

  int status;
  int result = fetch(url, sink, cap, status);
  sink.file.close();

  unsigned char err = fetch_error(result, status, http_status);
  if (result == FETCH_TRANSFER && sink.overflow) err = ERR_LARGE_DGRAM;
  if (result == FETCH_TRANSFER && sink.fs_error) err = ERR_STORAGE;
  if (err != ERR_OK) {
    LittleFS.remove(DL_FILE);
    publish_http_error(err, http_status);
    return;
  }

  // Phase 2: the TLS client is gone, the heap is free for the inflate window
  File z = LittleFS.open(DL_FILE, "r");
  if (!z) { publish_byte(ERR_STORAGE); return; }

  uint8_t sig[4];
  bool is_zip = z.read(sig, 4) == 4 && sig[0] == 'P' && sig[1] == 'K' && sig[2] == 3 && sig[3] == 4;

  if (is_zip) {
    // Capacity left for the extracted file next to the compressed one
    uint32_t cap2 = flash_capacity();
    err = unzip_first_rom(z, cap2);
    z.close();
    LittleFS.remove(DL_FILE);
    if (err != ERR_OK) {
      LittleFS.remove(ROM_FILE);
      publish_byte(err);
      return;
    }
  } else {
    // Plain file: keep it as is, compute its CRC
    rom_size = z.size();
    rom_crc = 0;
    z.seek(0, SeekSet);
    uint8_t buf[256];
    for (;;) {
      size_t n = z.read(buf, sizeof(buf));
      if (!n) break;
      rom_crc = crc32_update(rom_crc, buf, n);
      yield();
    }
    z.close();
    LittleFS.remove(ROM_FILE);
    if (!LittleFS.rename(DL_FILE, ROM_FILE)) { publish_byte(ERR_STORAGE); return; }
    strncpy(rom_name, display_name, LIST_NAME_MAX);
    rom_name[LIST_NAME_MAX] = 0;
  }

  rom_ready = true;
  publish_byte(ERR_OK);
  publish_dword(rom_size);
  publish_dword(rom_crc);
  publish_string(rom_name);
}

// --------------------------------------------------------------------------
// Commands
// --------------------------------------------------------------------------

void romloader_init() {
  LittleFS.begin();
  LittleFS.remove(DL_FILE);
  LittleFS.remove(ROM_FILE);
  LittleFS.remove(LIST_FILE);
  rom_ready = false;
  rom_name[0] = 0;
  list_count = 0;
  current_url = "";
}

// 0x40: url (zero terminated). Response: error [+ HTTP status], count (2 bytes)
void http_list_url() {
  String url = encode_spaces(get_string());
  if (!is_http_url(url)) { publish_byte(ERR_INV_PARAM); return; }
  unsigned int status;
  unsigned char err = do_list(url, status);
  publish_http_error(err, status);
  if (err == ERR_OK) publish_word(list_count);
}

// 0x41: start (2 bytes), count (1 byte), filter (zero terminated, "" = all).
// Response: error, matching entries (2 bytes), returned entries (1 byte), then
// for each entry: index (2 bytes), flags (1), size (4), name (zero terminated)
void http_list_get() {
  unsigned int start = get_word();
  unsigned int count = get_byte();
  char filter[FILTER_MAX + 1];
  strncpy(filter, get_string(), FILTER_MAX);
  filter[FILTER_MAX] = 0;
  for (char *p = filter; *p; p++) *p = tolower(*p);
  if (count > LIST_PAGE_MAX) count = LIST_PAGE_MAX;

  if (current_url.length() == 0) { publish_byte(ERR_INV_OPER); return; }

  struct PageEntry { uint16_t index; uint8_t flags; uint32_t size; char name[LIST_NAME_MAX + 1]; };
  PageEntry *page = (PageEntry *) malloc(sizeof(PageEntry) * (count ? count : 1));
  if (!page) { publish_byte(ERR_BUFFER); return; }

  File f = LittleFS.open(LIST_FILE, "r");
  if (!f) { free(page); publish_byte(ERR_STORAGE); return; }

  ListRecord r;
  unsigned int matched = 0, taken = 0;
  for (uint32_t index = 0; index < list_count; index++) {
    if (!read_record(f, r)) break;
    if (filter[0]) {
      char lower[LIST_NAME_MAX + 1];
      for (int i = 0; ; i++) { lower[i] = tolower(r.name[i]); if (!r.name[i]) break; }
      if (!strstr(lower, filter)) continue;
    }
    if (matched >= start && taken < count) {
      page[taken].index = index;
      page[taken].flags = r.flags;
      page[taken].size = r.size;
      strcpy(page[taken].name, r.name);
      taken++;
    }
    matched++;
    if ((index & 63) == 0) yield();
  }
  f.close();

  publish_byte(ERR_OK);
  publish_word(matched);
  publish_byte(taken);
  for (unsigned int i = 0; i < taken; i++) {
    publish_word(page[i].index);
    publish_byte(page[i].flags);
    publish_dword(page[i].size);
    publish_string(page[i].name);
  }
  free(page);
}

// 0x42: index (2 bytes) of a directory entry. Response as 0x40
void http_list_enter() {
  unsigned int index = get_word();
  ListRecord r;
  if (current_url.length() == 0 || !find_record(index, r)) { publish_byte(ERR_INV_PARAM); return; }
  if (!(r.flags & 1)) { publish_byte(ERR_INV_PARAM); return; }

  String url = resolve_url(current_url, r.href);
  if (!url.endsWith("/")) url += "/";
  unsigned int status;
  unsigned char err = do_list(url, status);
  publish_http_error(err, status);
  if (err == ERR_OK) publish_word(list_count);
}

// 0x43: parent directory. Response as 0x40 (error 15 at the root)
void http_list_up() {
  if (current_url.length() == 0) { publish_byte(ERR_INV_OPER); return; }
  String origin = url_origin(current_url);
  String path = current_url.substring(origin.length());
  while (path.endsWith("/")) path.remove(path.length() - 1);
  int cut = path.lastIndexOf('/');
  if (path.length() == 0 || cut < 0) { publish_byte(ERR_INV_OPER); return; }

  String url = origin + path.substring(0, cut + 1);
  unsigned int status;
  unsigned char err = do_list(url, status);
  publish_http_error(err, status);
  if (err == ERR_OK) publish_word(list_count);
}

// 0x44: index (2 bytes) of a file entry.
// Response: error [+ HTTP status]; on success size (4), CRC-32 (4), name (zero terminated)
void http_get_entry() {
  unsigned int index = get_word();
  ListRecord r;
  if (current_url.length() == 0 || !find_record(index, r)) { publish_byte(ERR_INV_PARAM); return; }
  if (r.flags & 1) { publish_byte(ERR_INV_PARAM); return; }

  String url = resolve_url(current_url, r.href);
  do_download(url, r.name);
}

// 0x45: url (zero terminated). Response as 0x44
void http_get_url() {
  String url = encode_spaces(get_string());
  if (!is_http_url(url)) { publish_byte(ERR_INV_PARAM); return; }
  char name[LIST_NAME_MAX + 1];
  url_basename(name, url, sizeof(name));
  do_download(url, name);
}

// 0x46: offset (4 bytes), length (2 bytes, up to MAX_FRAME).
// Response: error, length actually read (2 bytes), data
void file_read() {
  uint32_t offset = get_dword();
  unsigned int len = get_word();
  if (len > MAX_FRAME) len = MAX_FRAME;

  if (!rom_ready) { publish_byte(ERR_NO_DATA); return; }
  if (!rom_file) rom_file = LittleFS.open(ROM_FILE, "r");
  if (!rom_file) { publish_byte(ERR_STORAGE); return; }

  unsigned int n = 0;
  if (offset < rom_size && rom_file.seek(offset, SeekSet))
    n = rom_file.read((uint8_t *) receive_buffer, len);

  publish_byte(ERR_OK);
  publish_word(n);
  publish_block((unsigned char *) receive_buffer, n);
}

// 0x47: Response: error, current listing URL (zero terminated, "" = none)
void http_get_location() {
  publish_byte(ERR_OK);
  // NETROM keeps a 256 byte buffer for it
  if (current_url.length() > 255) publish_string(current_url.substring(0, 255).c_str());
  else publish_string(current_url.c_str());
}

// --------------------------------------------------------------------------
// Firmware update (OTA over HTTP/HTTPS)
// --------------------------------------------------------------------------

// Collects a short text answer (first line, trimmed) for OTA_CHECK
class TextSink : public SinkStream {
public:
  char text[64];
  size_t len = 0;
  bool done = false;

  TextSink() { text[0] = 0; }

  size_t write(uint8_t b) override {
    if (done) return 1;
    if (b == '\n' || b == '\r') { if (len) done = true; return 1; }
    if (len < sizeof(text) - 1 && b >= 0x20 && b < 0x7f) text[len++] = b;
    text[len] = 0;
    return 1;
  }

  size_t write(const uint8_t *data, size_t n) override {
    for (size_t i = 0; i < n; i++) write(data[i]);
    return n;
  }
};

// 0x50: url (zero terminated) of a small text file, e.g. version.txt.
// Response: error [+ HTTP status], then the first line of the file (zero terminated)
void ota_check() {
  String url = encode_spaces(get_string());
  if (!is_http_url(url)) { publish_byte(ERR_INV_PARAM); return; }
  if (WiFi.status() != WL_CONNECTED) { publish_byte(ERR_NO_NETWORK); return; }

  TextSink sink;
  int status;
  int result = fetch(url, sink, 4096, status);
  unsigned int http_status;
  unsigned char err = fetch_error(result, status, http_status);
  publish_http_error(err, http_status);
  if (err == ERR_OK) publish_string(sink.text);
}

// 0x51: url (zero terminated) of the firmware binary.
// Response: error (2 no network, 4 bad URL, 20 + description when the update
// failed). On success the error byte 0 is sent and the modem reboots at once:
// the host must reset it again (0x00) and wait for the "NiFi" signature.
void ota_update() {
  String url = encode_spaces(get_string());
  if (!is_http_url(url)) { publish_byte(ERR_INV_PARAM); return; }
  if (WiFi.status() != WL_CONNECTED) { publish_byte(ERR_NO_NETWORK); return; }

  // Free what we can: the updater needs the TLS buffers plus a flash sector
  discard_rom();
  close_tcp_all();
  close_udp_all();

  WiFiClient *client;
  if (starts_with_ci(url, "https://")) {
    BearSSL::WiFiClientSecure *c = new BearSSL::WiFiClientSecure();
    c->setInsecure();
    client = c;
  } else {
    client = new WiFiClient();
  }
  client->setTimeout(HTTP_TIMEOUT);

  ESPhttpUpdate.rebootOnUpdate(false);
  ESPhttpUpdate.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  ESPhttpUpdate.setLedPin(-1);
  t_httpUpdate_return r = ESPhttpUpdate.update(*client, url, VERSION);
  delete client;

  switch (r) {
    case HTTP_UPDATE_OK:
      publish_byte(ERR_OK);
      Serial.flush();
      delay(200);
      ESP.restart();
      break;

    case HTTP_UPDATE_NO_UPDATES:
      publish_byte(ERR_UPDATE);
      publish_string("the server reports no update (HTTP 304)");
      break;

    default: {
      publish_byte(ERR_UPDATE);
      String msg = ESPhttpUpdate.getLastErrorString();
      msg += " (";
      msg += ESPhttpUpdate.getLastError();
      msg += ")";
      publish_string(msg.c_str());
    }
  }
}

// 0x52: Response: error (always 0), flash chip size, sketch size and free
// space for an OTA image (three 32 bit values), then the running version string
void ota_info() {
  publish_byte(ERR_OK);
  publish_dword(ESP.getFlashChipRealSize());
  publish_dword(ESP.getSketchSize());
  publish_dword(ESP.getFreeSketchSpace());
  publish_string(VERSION);
}

// --------------------------------------------------------------------------
// Firmware update from the host (image sent over the UART, e.g. from a disk)
// --------------------------------------------------------------------------

static uint32_t ota_expected = 0;   // bytes announced by OTA_BEGIN
static uint32_t ota_received = 0;

static void publish_update_error() {
  static const char *names[] = {
    "ok", "flash write failed", "flash erase failed", "flash read failed",
    "not enough space", "bad size", "stream error", "MD5 mismatch",
    "flash config mismatch", "new flash config mismatch", "bad magic byte",
    "bootstrapping failed", "signature error", "no data", "out of memory" };
  int err = Update.getError();
  String msg = "update error ";
  msg += err;
  if (err >= 0 && err < (int) (sizeof(names) / sizeof(names[0]))) {
    msg += ": ";
    msg += names[err];
  }
  publish_byte(ERR_UPDATE);
  publish_string(msg.c_str());
}

// 0x53: size of the image (4 bytes). Response: error (20 + text when the
// image does not fit or an update is already running)
void ota_begin() {
  uint32_t size = get_dword();
  if (size == 0) { publish_byte(ERR_INV_PARAM); return; }

  discard_rom();
  if (Update.isRunning()) Update.end(false);
  Update.clearError();

  if (!Update.begin(size)) { publish_update_error(); return; }
  ota_expected = size;
  ota_received = 0;
  publish_byte(ERR_OK);
}

// 0x54: length (2 bytes, MAX_FRAME at most), data. Response: error
void ota_data() {
  unsigned int len = get_word();
  if (len > MAX_FRAME) {
    // The host sent more than we can buffer: drain it and refuse
    for (unsigned int i = 0; i < len; i++) get_byte();
    publish_byte(ERR_INV_PARAM);
    return;
  }
  get_block(len, (unsigned char *) receive_buffer);

  if (!Update.isRunning()) { publish_byte(ERR_INV_OPER); return; }
  if (ota_received + len > ota_expected) { publish_byte(ERR_INV_PARAM); return; }
  if (Update.write((uint8_t *) receive_buffer, len) != len) { publish_update_error(); return; }
  ota_received += len;
  publish_byte(ERR_OK);
}

// 0x55: Response: error. On success the modem reboots right after the
// answer, as with 0x51
void ota_end() {
  if (!Update.isRunning()) { publish_byte(ERR_INV_OPER); return; }
  if (ota_received != ota_expected || !Update.end(false)) { publish_update_error(); return; }
  publish_byte(ERR_OK);
  Serial.flush();
  delay(200);
  ESP.restart();
}

// 0x56: Response: error (always 0)
void ota_abort() {
  if (Update.isRunning()) Update.end(false);
  Update.clearError();
  ota_expected = ota_received = 0;
  publish_byte(ERR_OK);
}
