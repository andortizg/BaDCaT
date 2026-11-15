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

#include "netman.h"
#include "exchange.h"
#include "protocol.h"
#include "network.h"
#include "ESP8266WiFi.h"
#include "connection_manager.h"
#include "utils.h"
#include "configuration.h"

unsigned char frame[MAX_FRAME];

void resolve_request(char *domain) {
  IPAddress addr;

  if (WiFi.status() != WL_CONNECTED) {
    publish_byte(ERR_NO_NETWORK);

    return;
  }

  int err = WiFi.hostByName(domain, addr, 10000);

  if ((addr[0] == 0 &&
       addr[1] == 0 &&
       addr[2] == 0 &&
       addr[3] == 0) ||

      (addr[0] == 0xff &&
       addr[1] == 0xff &&
       addr[2] == 0xff &&
       addr[3] == 0xff)
      ) {
    publish_byte(ERR_DNS);

    return;
  }

  publish_byte(ERR_OK);
  publish_byte(addr[0]);
  publish_byte(addr[1]);
  publish_byte(addr[2]);
  publish_byte(addr[3]);
}

// ---------------------------------------------------------------------------
// TCP
// ---------------------------------------------------------------------------

static bool valid_tcp_conn(unsigned char n) {
  return n >= 1 && n <= MAX_SOCKETS;
}

static unsigned int slot_available(int n) {
  return pool[n].listening ? 0 : pool[n].client.available();
}

// Legacy command 0x10: error, state, available bytes. Never fails.
void tcp_status(unsigned char n)
{
  if (!valid_tcp_conn(n)) {
    publish_byte(ERR_OK);
    publish_byte(TCP_STATE_UNKNOWN);
    publish_word(0);

    return;
  }

  n--;
  tcp_poll_listeners();

  publish_byte(ERR_OK);
  publish_byte(tcp_slot_state(n));
  publish_word(slot_available(n));
}

// Command 0x13, everything TCPIP_TCP_STATE needs:
//   ERR_OK      -> remote IP (4), remote port (2), local port (2), state (1), flags (1), available bytes (2)
//   ERR_NO_CONN -> close reason (1)
void tcp_ext_status(unsigned char n) {
  if (!valid_tcp_conn(n)) {
    publish_byte(ERR_NO_CONN);
    publish_byte(CLOSE_UNKNOWN);

    return;
  }

  n--;
  tcp_poll_listeners();

  if (!tcp_slot_in_use(n)) {
    publish_byte(ERR_NO_CONN);
    publish_byte(tcp_slot_close_reason(n));

    return;
  }

  IPAddress ip;
  unsigned int rport, lport;

  if (pool[n].listening) {
    ip = IPAddress(pool[n].expect_ip);
    rport = pool[n].expect_port;
    lport = pool[n].local_port;
  } else {
    ip = pool[n].client.remoteIP();
    rport = pool[n].client.remotePort();
    lport = pool[n].client.localPort();
  }

  publish_byte(ERR_OK);
  publish_byte(ip[0]);
  publish_byte(ip[1]);
  publish_byte(ip[2]);
  publish_byte(ip[3]);
  publish_word(rport);
  publish_word(lport);
  publish_byte(tcp_slot_state(n));
  publish_byte(0);                 // flags: no TLS
  publish_word(slot_available(n));
}

void tcp_send(unsigned char n, unsigned int bs) {
  if (!valid_tcp_conn(n) || !tcp_slot_in_use(n - 1)) {
    publish_byte(ERR_NO_CONN);

    return;
  }

  n--;
  unsigned char st = tcp_slot_state(n);
  if (st != TCP_STATE_ESTABLISHED && st != TCP_STATE_CLOSE_WAIT) {
    publish_byte(ERR_CONN_STATE);

    return;
  }

  publish_byte(ERR_OK);
  while(bs > 0) {
    unsigned int to_load = min(bs, MAX_FRAME);

    get_block(to_load, frame);
    if (pool[n].client.connected())
      pool[n].client.write(frame, to_load);
    bs -= to_load;
  }
}

void tcp_recv(unsigned char n, unsigned int bs) {
  if (!valid_tcp_conn(n) || !tcp_slot_in_use(n - 1)) {
    publish_byte(ERR_NO_CONN);

    return;
  }

  n--;
  publish_byte(ERR_OK);

  unsigned int to_send = min(min(bs, slot_available(n)), MAX_FRAME);
  unsigned int actually = to_send ? pool[n].client.read(frame, to_send) : 0;
  publish_word(actually);
  publish_block(frame, actually);
}

// ---------------------------------------------------------------------------
// UDP
// ---------------------------------------------------------------------------

void udp_status(char n) {
  n--;
  if (n < 0 || n >= MAX_UDP_SOCKETS || !udp_pool[n].is_opened) {
    publish_byte(ERR_NO_CONN);

    return;
  }

  if (!udp_pool[n].is_parsed) {
    udp_pool[n].udp.parsePacket();
    udp_pool[n].is_parsed = true;

  }

  int avail = udp_pool[n].udp.available();
  if (avail == 0) udp_pool[n].is_parsed = false;

  publish_byte(ERR_OK);
  publish_word(udp_pool[n].port);
  publish_word(avail);
}

void upd_send(char n) {
  n--;

  unsigned char ip[4];
  for (int k = 0; k < 4; k++) ip[k] = get_byte();
  unsigned int port = get_word();
  unsigned int bs = get_word();

  if (n < 0 || n >= MAX_UDP_SOCKETS || !udp_pool[n].is_opened) {
    publish_byte(ERR_NO_CONN);

    return;
  }

  if (bs > MAX_FRAME) {
    publish_byte(ERR_LARGE_DGRAM);

    return;
  }

  publish_byte(ERR_OK);
  get_block(bs, frame);
  udp_pool[n].udp.beginPacket(IPAddress(ip), port);
  udp_pool[n].udp.write(frame, bs);
  udp_pool[n].udp.endPacket();
}

void udp_recv(char n, unsigned int bs) {
  n--;
  if (n < 0 || n >= MAX_UDP_SOCKETS || !udp_pool[n].is_opened) {
    publish_byte(ERR_NO_CONN);

    return;
  }
  if (!udp_pool[n].is_parsed)
    udp_pool[n].udp.parsePacket();

  // Next packets should be parsed
  udp_pool[n].is_parsed = false;

  unsigned int avail = udp_pool[n].udp.available();
  if (avail == 0) {
    publish_byte(ERR_NO_DATA);

    return;
  }

  publish_byte(ERR_OK);

  IPAddress rIp = udp_pool[n].udp.remoteIP();
  unsigned int rPort = udp_pool[n].udp.remotePort();
  publish_byte(rIp[0]);
  publish_byte(rIp[1]);
  publish_byte(rIp[2]);
  publish_byte(rIp[3]);

  publish_word(rPort);

  unsigned int to_send = min(min(bs, avail), MAX_FRAME);
  unsigned int actually = udp_pool[n].udp.read(frame, to_send);
  publish_word(actually);
  publish_block(frame, actually);
}
