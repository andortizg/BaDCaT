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

#include "protocol.h"
#include "exchange.h"
#include "connection_manager.h"
#include "netman.h"
#include "network.h"
#include "romloader.h"

#define current_caps     (CAP_RESOLVE_VIA_DNS | CAP_TCP_ACTIVE | CAP_TCP_PASSIVE_REMOTE_SOCKET | CAP_TCP_PASSIVE | CAP_OPEN_UPD | CAP_DHCP)
#define current_caps2    (CAP2_AUTO_IP | CAP2_AUTO_DNS)
#define current_features (FEAT_WIRELESS | FEAT_DNS_Q_BLOCKING | FEAT_TCP_OPEN_BLOCKING)
#define current_link     LINK_WIFI

void get_features() {
  switch(get_byte()) {
    case BLOCK_CAP_FLAGS:
      publish_byte(ERR_OK);
      publish_word(current_caps);
      break;
     case BLOCK_POOL_SIZE:
      publish_byte(ERR_OK);
      publish_byte(get_total_sockets());
      publish_byte(get_total_udp_sockets());
      publish_byte(get_free_sockets());
      publish_byte(get_free_udp_sockets());
      break;
     case BLOCK_MAX_FRAME:
      publish_byte(ERR_OK);
      publish_word(MAX_FRAME);
      publish_word(MAX_FRAME);
      break;
     case BLOCK_CAP_FLAGS2:
      publish_byte(ERR_OK);
      publish_word(current_caps2);
      publish_word(0);
      break;
     case BLOCK_FEATURES:
      publish_byte(ERR_OK);
      publish_word(current_features);
      publish_byte(current_link);
      break;
    default:
      publish_byte(ERR_INV_PARAM);
  }
}

void process_operation() {
  switch(get_byte()) {

    case OP_Reset:
      perform_reset();
      break;
    // INFO
    case OP_GET_FEATURES:
      get_features();
      break;

    case OP_GET_IP:
      get_ips(get_byte());
      break;

    case OP_GET_NETSTATE:
      get_netstatus();
      break;
    // GENERAL
    case OP_RESOLVE_DNS:
      resolve_request(get_string());
      break;
    // UDP
    case OP_OPEN_UDP:
      open_udp(get_word());
      break;

    case OP_CLOSE_UDP:
      close_udp(get_byte());
      break;

    case OP_STATUS_UDP:
      udp_status(get_byte());
      break;

    case OP_SEND_DATAGR:
      upd_send(get_byte());
      break;

    case OP_RECV_DATAGR: {
      unsigned char n = get_byte();
      udp_recv(n, get_word());
      break;
    }

    // TCP
    case OP_OPEN_TCP: {
      char ip[4];
      for (char i=0;i<4;++i) ip[i] = get_byte();

      open_tcp(ip, get_word());
      break;
    }

    case OP_OPEN_TCP_EX:
      open_tcp_ex();
      break;

    case OP_CLOSE_TCP:
      close_tcp(get_byte(), false);
      break;

    case OP_ABORT_TCP:
      close_tcp(get_byte(), true);
      break;

    case OP_STATUS_TCP:
      tcp_status(get_byte());
      break;

    case OP_EXT_STATUS_TCP:
      tcp_ext_status(get_byte());
      break;

    case OP_SEND_TCP: {
      unsigned char n = get_byte();
      tcp_send(n, get_word());
      break;
    }

    case OP_RECV_TCP: {
      unsigned char n = get_byte();
      tcp_recv(n, get_word());
      break;
    }

    // WIFI
    case OP_GET_AP_LIST:
      get_ap_list();
      break;

    case OP_GET_AP_LIST_EX:
      get_ap_list_ex();
      break;

    case OP_SET_AP: {
      char ssid[255];
      char passwd[255];
      strcpy(ssid, get_string());
      strcpy(passwd, get_string());
      set_ap(ssid, passwd);
      break;
    }

    case OP_GET_AP:
      get_current_ap();
      break;

    case OP_GET_RSSI:
      get_rssi();
      break;

    case OP_GET_MAC:
      get_mac();
      break;

    case OP_FORGET_AP:
      forget_ap();
      break;

    // ROM LOADER
    case OP_HTTP_LIST_URL:
      http_list_url();
      break;

    case OP_HTTP_LIST_GET:
      http_list_get();
      break;

    case OP_HTTP_LIST_ENTER:
      http_list_enter();
      break;

    case OP_HTTP_LIST_UP:
      http_list_up();
      break;

    case OP_HTTP_GET_ENTRY:
      http_get_entry();
      break;

    case OP_HTTP_GET_URL:
      http_get_url();
      break;

    case OP_FILE_READ:
      file_read();
      break;

    case OP_HTTP_LOCATION:
      http_get_location();
      break;

    // FIRMWARE UPDATE
    case OP_OTA_CHECK:
      ota_check();
      break;

    case OP_OTA_UPDATE:
      ota_update();
      break;

    case OP_OTA_INFO:
      ota_info();
      break;

    case OP_OTA_BEGIN:
      ota_begin();
      break;

    case OP_OTA_DATA:
      ota_data();
      break;

    case OP_OTA_END:
      ota_end();
      break;

    case OP_OTA_ABORT:
      ota_abort();
      break;

    // MODEM
    case OP_VERSION_STR:
      publish_byte(ERR_OK);
      publish_string(version_str);
      break;

    default:
      publish_byte(ERR_NOT_IMP);
  }
}
