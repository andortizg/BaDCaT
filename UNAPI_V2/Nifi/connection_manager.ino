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

#include "connection_manager.h"
#include "ESP8266WiFi.h"
#include "configuration.h"
#include "udp_wrapper.h"
#include "tcp_slot.h"
#include "exchange.h"
#include "protocol.h"

TcpSlot pool[MAX_SOCKETS];
TcpListener listeners[MAX_SOCKETS];
UdpWrapper udp_pool[MAX_UDP_SOCKETS];

// ---------------------------------------------------------------------------
// TCP slots
// ---------------------------------------------------------------------------

unsigned char get_total_sockets() {
  return MAX_SOCKETS;
}

// A slot is busy while it listens, while lwIP still owns a control block for
// it, or while unread data is pending. A connection closed by the remote host
// (and fully read) becomes free again, exactly like InterNestor does.
bool tcp_slot_in_use(int i) {
  if (i < 0 || i >= MAX_SOCKETS) return false;
  if (pool[i].listening) return true;
  return pool[i].client.status() != CLOSED || pool[i].client.available() > 0;
}

// UNAPI connection state. lwIP uses the very same numbering, so the only
// special cases are LISTEN (handled by us, not by a client pcb) and a closed
// pcb that still holds unread data (reported as CLOSE-WAIT).
unsigned char tcp_slot_state(int i) {
  if (pool[i].listening) return TCP_STATE_LISTEN;
  unsigned char st = pool[i].client.status();
  if (st == CLOSED)
    return pool[i].client.available() > 0 ? TCP_STATE_CLOSE_WAIT : TCP_STATE_UNKNOWN;
  return st;
}

unsigned char tcp_slot_close_reason(int i) {
  unsigned char r = pool[i].close_reason;
  if (r == CLOSE_UNKNOWN && WiFi.status() != WL_CONNECTED) r = CLOSE_NETWORK_LOST;
  return r;
}

unsigned char get_free_sockets() {
  int counter = 0;
  for (int i = 0; i < MAX_SOCKETS; i++)
    if (!tcp_slot_in_use(i)) counter++;

  return counter;
}

static int find_free_slot() {
  for (int i = 0; i < MAX_SOCKETS; i++)
    if (!tcp_slot_in_use(i)) return i;

  return -1;
}

static bool remote_specified(int i) {
  return (pool[i].expect_ip[0] | pool[i].expect_ip[1] | pool[i].expect_ip[2] | pool[i].expect_ip[3]) != 0;
}

static unsigned int slot_local_port(int i) {
  return pool[i].listening ? pool[i].local_port : pool[i].client.localPort();
}

static void slot_remote(int i, IPAddress &ip, unsigned int &port) {
  if (pool[i].listening) {
    ip = IPAddress(pool[i].expect_ip);
    port = pool[i].expect_port;
  } else {
    ip = pool[i].client.remoteIP();
    port = pool[i].client.remotePort();
  }
}

// ---------------------------------------------------------------------------
// Listeners (passive connections)
// ---------------------------------------------------------------------------

// Reject every client still queued on a listening socket
static void drain_listener(int l) {
  while (listeners[l].server.hasClient()) {
    WiFiClient c = listeners[l].server.accept();
    if (c.status() != CLOSED) c.abort();
  }
}

static void release_listener(int i) {
  int l = pool[i].listener;
  pool[i].listener = -1;
  if (l < 0) return;

  if (listeners[l].refs > 0) listeners[l].refs--;
  if (listeners[l].refs == 0) {
    drain_listener(l);
    listeners[l].server.close();
    listeners[l].port = 0;
  }
}

// Returns the listener index, -1 if the pool is exhausted, -2 if the port
// could not be bound (already used by another socket).
static int acquire_listener(unsigned int port) {
  int l;

  for (l = 0; l < MAX_SOCKETS; l++)
    if (listeners[l].refs > 0 && listeners[l].port == port) {
      listeners[l].refs++;
      return l;
    }

  for (l = 0; l < MAX_SOCKETS; l++)
    if (listeners[l].refs == 0) break;
  if (l == MAX_SOCKETS) return -1;

  listeners[l].server.begin(port, LISTEN_BACKLOG);
  if (listeners[l].server.status() != LISTEN) return -2;

  listeners[l].server.setNoDelay(IS_NO_DELAY);
  listeners[l].port = port;
  listeners[l].refs = 1;
  return l;
}

// Hand queued incoming connections to the passive slots waiting for them.
// Slots that expect a specific remote socket have priority over slots with
// an unspecified remote socket; a client nobody wants is reset.
void tcp_poll_listeners() {
  for (int l = 0; l < MAX_SOCKETS; l++) {
    if (listeners[l].refs == 0) continue;

    while (listeners[l].server.hasClient()) {
      WiFiClient c = listeners[l].server.accept();
      if (c.status() == CLOSED) continue;

      int target = -1;

      for (int i = 0; i < MAX_SOCKETS && target < 0; i++) {
        if (!pool[i].listening || pool[i].listener != l || !remote_specified(i)) continue;
        if (c.remoteIP() == IPAddress(pool[i].expect_ip) && c.remotePort() == pool[i].expect_port)
          target = i;
      }

      for (int i = 0; i < MAX_SOCKETS && target < 0; i++)
        if (pool[i].listening && pool[i].listener == l && !remote_specified(i))
          target = i;

      if (target < 0) {
        c.abort();
        continue;
      }

      c.setNoDelay(IS_NO_DELAY);
      c.setSync(IS_SYNC);
      pool[target].client = c;
      pool[target].listening = false;
      pool[target].close_reason = CLOSE_UNKNOWN;
      release_listener(target);
    }
  }
}

// ---------------------------------------------------------------------------
// Open
// ---------------------------------------------------------------------------

static void prepare_slot(int i, unsigned char *ip, unsigned int rport, unsigned int lport, bool resident) {
  pool[i].client = WiFiClient();   // drop any leftover context from a previous use
  pool[i].listening = false;
  pool[i].listener = -1;
  pool[i].resident = resident;
  pool[i].close_reason = CLOSE_UNKNOWN;
  memcpy(pool[i].expect_ip, ip, 4);
  pool[i].expect_port = rport;
  pool[i].local_port = lport;
}

// Active open. Blocks until the connection is established or the timeout
// expires (features flag "TCP_OPEN is blocking" is advertised).
static void connect_slot(int i, unsigned char *ip, unsigned int rport, unsigned int lport, unsigned long ms) {
  if (lport) WiFiClient::setLocalPortStart(lport);
  pool[i].client.setTimeout(ms);

  unsigned long started = millis();
  int ok = pool[i].client.connect(IPAddress(ip), rport);

  if (lport) WiFiClient::setLocalPortStart(0);

  if (ok) {
    pool[i].client.setNoDelay(IS_NO_DELAY);
    pool[i].client.setSync(IS_SYNC);

    publish_byte(ERR_OK);
    publish_byte(i + 1);
    return;
  }

  pool[i].client = WiFiClient();
  // A quick failure means the peer answered with RST, otherwise nobody answered
  pool[i].close_reason = (millis() - started + 500 < ms) ? CLOSE_RST_RECEIVED : CLOSE_ESTABLISH_TIMEOUT;

  publish_byte(ERR_NO_CONN);
  publish_byte(pool[i].close_reason);
}

// Legacy command 0x0D: active open with remote IP and port only
void open_tcp(char *addr, unsigned int port) {
  unsigned char ip[4];
  for (int k = 0; k < 4; k++) ip[k] = addr[k];

  if (WiFi.status() != WL_CONNECTED) {
    publish_byte(ERR_NO_NETWORK);
    return;
  }

  int i = find_free_slot();
  if (i < 0) {
    publish_byte(ERR_NO_FREE_CONN);
    return;
  }

  prepare_slot(i, ip, port, 0, false);
  connect_slot(i, ip, port, 0, DEFAULT_CONNECT_TIMEOUT);
}

// Command 0x14: the UNAPI TCPIP_TCP_OPEN parameter block
//   +0 (4) remote IP (0.0.0.0 = unspecified, passive only)
//   +4 (2) remote port
//   +6 (2) local port (#FFFF = random)
//   +8 (2) user timeout in seconds (0 = default, #FFFF = infinite)
//  +10 (1) flags: bit 0 passive, bit 1 resident, bit 2 TLS, bit 3 verify certificate
// Response: error code, then connection number (ERR_OK) or close reason (ERR_NO_CONN)
void open_tcp_ex() {
  unsigned char ip[4];
  for (int k = 0; k < 4; k++) ip[k] = get_byte();
  unsigned int rport = get_word();
  unsigned int lport = get_word();
  unsigned int timeout = get_word();
  unsigned char flags = get_byte();

  bool passive = flags & TCP_FLAG_PASSIVE;
  bool any_remote = (ip[0] | ip[1] | ip[2] | ip[3]) == 0;

  if (flags & 0xF0) {
    publish_byte(ERR_INV_PARAM);
    return;
  }

  if (flags & (TCP_FLAG_TLS | TCP_FLAG_VERIFY)) {
    publish_byte(ERR_NOT_IMP);
    return;
  }

  if ((timeout != 0 && timeout != 0xffff && timeout > 1080) || (!passive && any_remote)) {
    publish_byte(ERR_INV_PARAM);
    return;
  }

  if (WiFi.status() != WL_CONNECTED) {
    publish_byte(ERR_NO_NETWORK);
    return;
  }

  if (lport == 0xffff) lport = passive ? random(16384, 32767) : 0;   // 0: lwIP picks one
  if (passive && any_remote) rport = 0xffff;

  // Only one connection per (local port, remote IP, remote port) is allowed,
  // except for passive connections with an unspecified remote socket.
  if (lport != 0 && !(passive && any_remote)) {
    for (int i = 0; i < MAX_SOCKETS; i++) {
      if (!tcp_slot_in_use(i) || slot_local_port(i) != lport) continue;

      IPAddress rip;
      unsigned int rp;
      slot_remote(i, rip, rp);

      if (rip == IPAddress(ip) && rp == rport) {
        publish_byte(ERR_CONN_EXISTS);
        return;
      }
    }
  }

  int i = find_free_slot();
  if (i < 0) {
    publish_byte(ERR_NO_FREE_CONN);
    return;
  }

  prepare_slot(i, ip, rport, lport, flags & TCP_FLAG_RESIDENT);

  if (passive) {
    int l = acquire_listener(lport);
    if (l == -1) {
      publish_byte(ERR_NO_FREE_CONN);
      return;
    }
    if (l == -2) {
      publish_byte(ERR_CONN_EXISTS);
      return;
    }

    pool[i].listener = l;
    pool[i].listening = true;

    publish_byte(ERR_OK);
    publish_byte(i + 1);
    return;
  }

  unsigned long ms;
  if (timeout == 0) ms = DEFAULT_CONNECT_TIMEOUT;
  else if (timeout == 0xffff) ms = MAX_CONNECT_TIMEOUT;
  else ms = timeout * 1000UL;

  connect_slot(i, ip, rport, lport, ms);
}

// ---------------------------------------------------------------------------
// Close
// ---------------------------------------------------------------------------

static void do_close(int i, bool abort) {
  if (pool[i].listening) {
    pool[i].listening = false;
    release_listener(i);
  } else if (abort) {
    pool[i].client.abort();
  } else {
    pool[i].client.stop();
  }

  pool[i].client = WiFiClient();
  pool[i].close_reason = abort ? CLOSE_BY_ABORT : CLOSE_BY_CLOSE;
}

// n = 0 closes every transient connection
void close_tcp(unsigned char n, bool abort) {
  if (n == 0) {
    for (int i = 0; i < MAX_SOCKETS; i++)
      if (tcp_slot_in_use(i) && !pool[i].resident) do_close(i, abort);

    publish_byte(ERR_OK);
    return;
  }

  n--;
  if (n >= MAX_SOCKETS || !tcp_slot_in_use(n)) {
    publish_byte(ERR_NO_CONN);
    return;
  }

  do_close(n, abort);
  publish_byte(ERR_OK);
}

void close_tcp_all() {
  for (int i = 0; i < MAX_SOCKETS; i++) {
    if (tcp_slot_in_use(i)) do_close(i, true);
    pool[i].close_reason = CLOSE_NEVER_USED;
    pool[i].resident = false;
  }
}

// ---------------------------------------------------------------------------
// UDP
// ---------------------------------------------------------------------------

unsigned char get_total_udp_sockets() {
  return MAX_UDP_SOCKETS;
}

unsigned char get_free_udp_sockets() {
  int counter = 0;
  for (int i=0;i<MAX_UDP_SOCKETS;i++)
    if (udp_pool[i].is_opened || udp_pool[i].udp.available() > 0)
      counter++;

  return MAX_UDP_SOCKETS - counter;
}

void open_udp(unsigned int port)
{
    if (get_free_udp_sockets() == 0) {
        publish_byte(ERR_NO_FREE_CONN);

        return;
    }

    // Unspecified port - random it
    if (port == 0xffff || port == 0)
      port = random(16384, 32767);

    char i;
    for (i=0;i<MAX_UDP_SOCKETS;i++)
      if (!udp_pool[i].is_opened) break;

    if (udp_pool[i].udp.begin(port)) {
      udp_pool[i].is_opened = true;
      udp_pool[i].port = port;
      udp_pool[i].is_parsed = false;

      publish_byte(ERR_OK);
      publish_byte(i + 1);

      return;
    }

    publish_byte(ERR_CONN_EXISTS);
}

void close_udp(char n) {
  n--;
  if (n < 0 || n >= MAX_UDP_SOCKETS) {
    publish_byte(ERR_NO_CONN);

    return;
  }

  if (udp_pool[n].is_opened) {
    udp_pool[n].udp.stop();
    udp_pool[n].is_opened = false;
    publish_byte(ERR_OK);

    return;
  }

  publish_byte(ERR_CONN_STATE);
}

void close_udp_all() {
  for (int i=0;i<MAX_UDP_SOCKETS;i++) {
      udp_pool[i].udp.stop();
      udp_pool[i].is_opened = false;
    }
}
