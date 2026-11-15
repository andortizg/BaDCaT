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

// Seconds to wait for an association when connecting to an AP
#define CONNECT_WAIT_SECONDS 15
// Scan results above this count are ignored (keeps the index table small)
#define MAX_SCAN_RESULTS 32

static char confByte;

void set_conf_byte(char b)  {
  if (b & 0xfc) {
    publish_byte(ERR_INV_PARAM);

    return;
  }

  if (b==0) {
    WiFi.disconnect(true);
    delay(1000);
    WiFi.begin();
    WiFi.config(0U, 0U, 0U);
  }
  confByte = b;

  publish_byte(ERR_OK);
}

void get_conf_byte() {
  publish_byte(ERR_OK);

  publish_byte(confByte);
}


void netman_init() {
  WiFi.persistent(true);
  WiFi.mode(WIFI_STA);
  WiFi.setAutoConnect(true);
  WiFi.setAutoReconnect(true);
}

// Legacy command 0x30: list of SSIDs terminated by 0xFF
void get_ap_list() {
    int n = WiFi.scanNetworks();
    if (n <= 0) {
      publish_byte(ERR_NO_NETWORK);

      return;
    }

    publish_byte(ERR_OK);
    for (int i = 0;i < n; ++i) {
      publish_string(WiFi.SSID(i).c_str());
    }

    publish_byte(0xff);
    WiFi.scanDelete();
}

// Command 0x36: entries of SSID (zero terminated), RSSI (signed byte, dBm)
// and encryption flag (0 = open, 1 = secured), strongest first, terminated
// by 0xFF.
void get_ap_list_ex() {
    int n = WiFi.scanNetworks();
    if (n <= 0) {
      publish_byte(ERR_NO_NETWORK);

      return;
    }
    if (n > MAX_SCAN_RESULTS) n = MAX_SCAN_RESULTS;

    int order[MAX_SCAN_RESULTS];
    for (int i = 0; i < n; i++) order[i] = i;

    // Insertion sort by signal strength, strongest first
    for (int i = 1; i < n; i++) {
      int k = order[i];
      int j = i - 1;
      while (j >= 0 && WiFi.RSSI(order[j]) < WiFi.RSSI(k)) {
        order[j + 1] = order[j];
        j--;
      }
      order[j + 1] = k;
    }

    publish_byte(ERR_OK);
    for (int i = 0; i < n; i++) {
      int idx = order[i];
      int rssi = WiFi.RSSI(idx);
      if (rssi < -127) rssi = -127;
      if (rssi > 0) rssi = 0;

      publish_string(WiFi.SSID(idx).c_str());
      publish_byte((signed char) rssi);
      publish_byte(WiFi.encryptionType(idx) == ENC_TYPE_NONE ? 0 : 1);
    }

    publish_byte(0xff);
    WiFi.scanDelete();
}

void get_current_ap() {
    if (WiFi.status() != WL_CONNECTED) {
      publish_byte(ERR_NO_NETWORK);

      return;
    }

    publish_byte(ERR_OK);
    publish_string(WiFi.SSID().c_str());
}

// Credentials are stored in flash by the SDK (persistent mode), so the modem
// reconnects by itself after a power cycle.
void set_ap(char *ssid, char *pass) {
    int counter = 0;
    WiFi.disconnect();

    for (int i=0;i<1000;i++) yield();

    if (pass[0] == 0)
      WiFi.begin(ssid);
    else
      WiFi.begin(ssid, pass);

    while(WiFi.status() != WL_CONNECTED && counter < CONNECT_WAIT_SECONDS) {
      yield();
      delay(1000);
      ++ counter;
    }

    switch (WiFi.status()) {
      case WL_CONNECTED:
        publish_byte(ERR_OK);
        break;

      case WL_NO_SSID_AVAIL:
        publish_byte(ERR_NO_NETWORK);
        break;

      default:
        publish_byte(ERR_AUTH_FAILED);
    }
}

// Command 0x35: disconnect and erase the stored credentials
void forget_ap() {
    WiFi.disconnect(true);
    delay(100);
    WiFi.mode(WIFI_STA);

    publish_byte(ERR_OK);
}

// Command 0x33: RSSI of the current AP as a signed byte (dBm)
void get_rssi() {
    if (WiFi.status() != WL_CONNECTED) {
      publish_byte(ERR_NO_NETWORK);

      return;
    }

    int rssi = WiFi.RSSI();
    if (rssi < -127) rssi = -127;
    if (rssi > 0) rssi = 0;

    publish_byte(ERR_OK);
    publish_byte((signed char) rssi);
}

// Command 0x34: station MAC address, 6 bytes
void get_mac() {
    uint8_t mac[6];
    WiFi.macAddress(mac);

    publish_byte(ERR_OK);
    for (int i = 0; i < 6; i++) publish_byte(mac[i]);
}

void get_ips(char t) {
  if (t < 1 || t > 6) {
    publish_byte(ERR_INV_PARAM);

    return;
  }

  if (WiFi.status() != WL_CONNECTED) {
    publish_byte(ERR_NO_NETWORK);

    return;
  }

  publish_byte(ERR_OK);
  IPAddress ip;
  switch(t) {

    case IP_LOCAL:
       ip = WiFi.localIP();
       break;

    case IP_REMOTE:
    case IP_GATEWAY:
      ip = WiFi.gatewayIP();
      break;

    case IP_MASK:
      ip = WiFi.subnetMask();
      break;

    case IP_DNS1:
      ip = WiFi.dnsIP(0);
      break;

    case IP_DNS2:
      ip = WiFi.dnsIP(1);
      break;

    default:
      ip = IPAddress((uint32_t) 0);
  }

  publish_byte(ip[0]);
  publish_byte(ip[1]);
  publish_byte(ip[2]);
  publish_byte(ip[3]);
}

void get_netstatus() {
  publish_byte(ERR_OK);

  switch(WiFi.status()) {
    case WL_IDLE_STATUS:
      publish_byte(NETWORK_OPENING);
      return;

    case WL_CONNECTED:
      publish_byte(NETWORK_OPEN);
      return;

    case WL_CONNECT_FAILED:
    case WL_CONNECTION_LOST:
    case WL_NO_SSID_AVAIL:
    case WL_DISCONNECTED:
      publish_byte(NETWORK_CLOSED);
      return;

    default:
      publish_byte(NETWORK_UNKNOWN);
  }
}
