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

#ifndef PROTOCOL_H
#define PROTOCOL_H

enum ErrorCodes {
    ERR_OK           = 0,
    ERR_NOT_IMP      = 1,
    ERR_NO_NETWORK   = 2,
    ERR_NO_DATA      = 3,
    ERR_INV_PARAM    = 4,
    ERR_QUERY_EXISTS = 5,
    ERR_INV_IP       = 6,
    ERR_NO_DNS       = 7,
    ERR_DNS          = 8,
    ERR_NO_FREE_CONN = 9,
    ERR_CONN_EXISTS  = 10,
    ERR_NO_CONN      = 11,
    ERR_CONN_STATE   = 12,
    ERR_BUFFER       = 13,
    ERR_LARGE_DGRAM  = 14,
    ERR_INV_OPER     = 15,
    ERR_AUTH_FAILED  = 16,
    // NiFi extensions (ROM loader, firmware 0.3+)
    ERR_HTTP         = 17,   // followed by a 16 bit HTTP status (0 = could not connect, 1 = transfer failed, 2 = redirect loop)
    ERR_BAD_ARCHIVE  = 18,   // corrupt or unsupported zip / no file inside
    ERR_STORAGE      = 19,   // flash file system error (full or not mounted)
    ERR_UPDATE       = 20    // OTA update failed: followed by a zero terminated description
};

enum CapabilitiesSet {
   CAP_SEND_ICMP                 = 1,
   CAP_RESOLVE_VIA_HOSTS         = 2,
   CAP_RESOLVE_VIA_DNS           = 4,
   CAP_TCP_ACTIVE                = 8,
   CAP_TCP_PASSIVE_REMOTE_SOCKET = 16,
   CAP_TCP_PASSIVE               = 32,
   CAP_TCP_URGENT                = 64,
   CAP_TCP_PUSH_BIT              = 128,
   CAP_TCP_SEND_BEFORE_ESTABLISH = 256,
   CAP_DISCARD_DATA_TCP          = 512,
   CAP_OPEN_UPD                  = 1024,
   CAP_OPEN_RAW_IP               = 2048,
   CAP_SET_TTL_TOS               = 4096,
   CAP_SET_AUTOREPLY_PING        = 8192,
   CAP_DHCP                      = 16384,
   CAP_GET_TTL_TOS_FOR_SENDING   = 32768
};

// Second capabilities word (UNAPI TCP/IP 1.1, TCPIP_GET_CAPAB block 4)
enum CapabilitiesSet2 {
   CAP2_AUTO_IP        = 1,     // Automatic local IP / mask / gateway (DHCP)
   CAP2_AUTO_DNS       = 2,     // Automatic DNS server addresses
   CAP2_MANUAL_IP      = 4,
   CAP2_MANUAL_PEER    = 8,
   CAP2_MANUAL_MASK    = 16,
   CAP2_MANUAL_GATEWAY = 32,
   CAP2_MANUAL_DNS1    = 64,
   CAP2_MANUAL_DNS2    = 128,
   CAP2_TLS_ACTIVE     = 256,
   CAP2_TLS_PASSIVE    = 512
};

// Features flags (UNAPI TCP/IP 1.1, TCPIP_GET_CAPAB block 1, register DE)
enum FeaturesSet {
   FEAT_POINT_TO_POINT     = 1,
   FEAT_WIRELESS           = 2,
   FEAT_SHARED_POOL        = 4,
   FEAT_NETSTATE_EXPENSIVE = 8,
   FEAT_HW_ASSISTED        = 16,
   FEAT_LOOPBACK           = 32,
   FEAT_DNS_CACHE          = 64,
   FEAT_IP_FRAGMENTATION   = 128,
   FEAT_USER_TIMEOUT       = 256,
   FEAT_TTL_IN_ECHO        = 512,
   FEAT_DNS_Q_BLOCKING     = 1024,
   FEAT_TCP_OPEN_BLOCKING  = 2048,
   FEAT_CERT_VERIFICATION  = 4096
};

enum LinkLevelProtocol {
  LINK_OTHER    = 0,
  LINK_SLIP     = 1,
  LINK_PPP      = 2,
  LINK_ETHERNET = 3,
  LINK_WIFI     = 4
};

enum IpAddresses {
    IP_LOCAL = 1,
    IP_REMOTE = 2,
    IP_MASK = 3,
    IP_GATEWAY = 4,
    IP_DNS1 = 5,
    IP_DNS2 = 6
};

enum FeatureBlocks {
  BLOCK_CAP_FLAGS  = 1,
  BLOCK_POOL_SIZE  = 2,
  BLOCK_MAX_FRAME  = 3,
  BLOCK_CAP_FLAGS2 = 4,   // Second capabilities and features words
  BLOCK_FEATURES   = 5    // NiFi extension: features flags + link level protocol
};


enum NetworkState {
  NETWORK_CLOSED  = 0,
  NETWORK_OPENING = 1,
  NETWORK_OPEN    = 2,
  NETWORK_CLOSING = 3,
  NETWORK_UNKNOWN = 255
};

// TCP connection states. Numbering is identical to UNAPI TCP/IP and to lwIP's tcp_state.
enum TCPState {
  TCP_STATE_UNKNOWN     = 0,
  TCP_STATE_LISTEN      = 1,
  TCP_STATE_SYN_SENT    = 2,
  TCP_STATE_SYN_RCVD    = 3,
  TCP_STATE_ESTABLISHED = 4,
  TCP_STATE_FIN_WAIT_1  = 5,
  TCP_STATE_FIN_WAIT_2  = 6,
  TCP_STATE_CLOSE_WAIT  = 7,
  TCP_STATE_CLOSING     = 8,
  TCP_STATE_LAST_ACK    = 9,
  TCP_STATE_TIME_WAIT   = 10
};

// Close reasons (UNAPI TCP/IP 1.1, TCPIP_TCP_STATE register C when the connection no longer exists)
enum TCPCloseReason {
  CLOSE_UNKNOWN           = 0,
  CLOSE_NEVER_USED        = 1,
  CLOSE_BY_CLOSE          = 2,   // TCPIP_TCP_CLOSE was called
  CLOSE_BY_ABORT          = 3,   // TCPIP_TCP_ABORT was called
  CLOSE_RST_RECEIVED      = 4,
  CLOSE_USER_TIMEOUT      = 5,
  CLOSE_ESTABLISH_TIMEOUT = 6,
  CLOSE_NETWORK_LOST      = 7,
  CLOSE_UNREACHABLE       = 8
};

// Flags byte of the TCPIP_TCP_OPEN parameter block
enum TCPOpenFlags {
  TCP_FLAG_PASSIVE  = 1,
  TCP_FLAG_RESIDENT = 2,
  TCP_FLAG_TLS      = 4,
  TCP_FLAG_VERIFY   = 8
};

enum ProtocolOperations {
  OP_Reset          = 0x00,
  OP_GET_FEATURES   = 0x01,
  OP_GET_IP         = 0x02,
  OP_GET_NETSTATE   = 0x03,
  OP_RESOLVE_DNS    = 0x06,
  OP_OPEN_UDP       = 0x08,
  OP_CLOSE_UDP      = 0x09,
  OP_STATUS_UDP     = 0x0A,
  OP_SEND_DATAGR    = 0x0B,
  OP_RECV_DATAGR    = 0x0C,
  OP_OPEN_TCP       = 0x0D,   // Legacy: active open, IP + port only
  OP_CLOSE_TCP      = 0x0E,
  OP_STATUS_TCP     = 0x10,   // Legacy: state + available bytes
  OP_SEND_TCP       = 0x11,
  OP_RECV_TCP       = 0x12,
  OP_EXT_STATUS_TCP = 0x13,   // Full UNAPI state: socket info, state, close reason, available bytes
  OP_OPEN_TCP_EX    = 0x14,   // UNAPI TCPIP_TCP_OPEN parameter block (active or passive)
  OP_ABORT_TCP      = 0x15,   // Abort (RST) a connection
  OP_CONF_AUTO_IP   = 0x19,
  OP_CONF_IP        = 0x1A,
  OP_GET_AP_LIST    = 0x30,
  OP_SET_AP         = 0x31,
  OP_GET_AP         = 0x32,
  OP_GET_RSSI       = 0x33,   // Signal strength of the current AP
  OP_GET_MAC        = 0x34,   // Station MAC address
  OP_FORGET_AP      = 0x35,   // Disconnect and erase stored credentials
  OP_GET_AP_LIST_EX = 0x36,   // AP list with signal strength and encryption flag
  // ROM loader (firmware 0.3+)
  OP_HTTP_LIST_URL   = 0x40,  // Fetch and parse the directory listing of an URL
  OP_HTTP_LIST_GET   = 0x41,  // Page of the current listing, with optional filter
  OP_HTTP_LIST_ENTER = 0x42,  // List a directory entry of the current listing
  OP_HTTP_LIST_UP    = 0x43,  // List the parent of the current location
  OP_HTTP_GET_ENTRY  = 0x44,  // Download (and unzip) a file entry to flash
  OP_HTTP_GET_URL    = 0x45,  // Download (and unzip) an URL to flash
  OP_FILE_READ       = 0x46,  // Read a block of the downloaded file
  OP_HTTP_LOCATION   = 0x47,  // Current listing URL
  // Firmware update (firmware 0.3+)
  OP_OTA_CHECK       = 0x50,  // Fetch a small text file (published version) from an URL
  OP_OTA_UPDATE      = 0x51,  // Download a firmware binary from an URL, flash it and reboot
  OP_OTA_INFO        = 0x52,  // Flash size, sketch size and free space for OTA
  OP_OTA_BEGIN       = 0x53,  // Start receiving a firmware image from the host (size)
  OP_OTA_DATA        = 0x54,  // Block of the image
  OP_OTA_END         = 0x55,  // Image complete: activate it and reboot
  OP_OTA_ABORT       = 0x56,  // Discard a partially received image
  OP_VERSION_STR    = 0xff
};

void process_operation();
#endif
