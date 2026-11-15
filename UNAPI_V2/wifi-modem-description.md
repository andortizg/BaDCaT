# Wifi modem protocol description

Protocol should have version and feature control, modular design and should be applied for different retro-computers as hardware TCP stack.

Currently main transport is UART. UART selected cause there is already existing solutions for ESP+Uart.

Resulting firmware should be used as dropin replacement for AT-commands firmware.

Exchange should be based on binary protocol to minimize parsing process and make it quicker.

## Exchange description 

All exchange should be implemented in `request->response` paradigm. 

Data flow is pull-based(if we talking about modem side) to prevent losing data. 

### Request description

Basic request can be present in next view:
 
 * One byte: command

 * Optional parameters:
  
   + All strings are zero terminated

   + IP addresses present as 4 bytes(lexical ordered B0.B1.B2.B3, currently IPv4 only)

   + Ports present as 2 bytes

   + All multibyte data are little-endian

Commands without parameters contains only one byte. 

### Response description

Basic response can be present in next view:

 * One byte: error code(zero for success)

 * Optional result artifacts(basic rules are the same as for request)

### Error codes

Based on UNAPI TCP/IP.


| Code    | Description                          |
|---------|--------------------------------------|
| 0       | Operation completed succefully       |
| 1       | Not implemented                      |
| 2       | No network connection available      |
| 3       | No incoming data available           |
| 4       | Invalid input parameter              |
| 5       | Another query is already in progress |
| 6       | Invalid IP address                   |
| 7       | No DNS servers are configured        |
| 8       | Error returned by DNS server         |
| 9       | No free connections available        |
| 10      | Connection already exists            |
| 11      | Connection does not exists           |
| 12      | Invalid connection state             |
| 13      | Insufficient output buffer space     |
| 14      | Datagram is too large                |
| 15      | Invalid operation                    |
| 16      | Auth failed                          |
| 17      | HTTP error (NiFi, firmware 0.3+): followed by a 16 bit status. 0 = could not connect, 1 = transfer failed, 2 = too many redirects, otherwise the HTTP status code |
| 18      | Bad archive (NiFi, firmware 0.3+): corrupt or unsupported zip, or no file inside |
| 19      | Flash storage error (NiFi, firmware 0.3+): file system missing or full |
| 20      | Firmware update failed (NiFi, firmware 0.3+): followed by a zero-terminated description |

## Commands description

### 0x00 - Reset

Return modem to initial state(close all connections wait for new commands).

Driver should begin work with this command. If there isn't right response - retry this operation.

Always should be succefull.

Return:

 * Success status code
 * "NiFi" magic zero-terminated string

### 0x01 - Get information about the TCP/IP capabilities and features

Parameters:

 * Index of information block to retrieve:
 
   + 1: Capabilities flags
   + 2: Connection pool size and status
   + 3: Maximum datagram size allowed
  
Response:

 * Wrong block: `Invalid input parameter` error(code 4)

 * 1 - Capabilities(success error code and 2 bytes response):
   
   + Bit 0: Send ICMP echo messages (PINGs) and retrieve the answers
   + Bit 1: Resolve host names by querying a local hosts file or database
   + Bit 2: Resolve host names by querying a DNS server
   + Bit 3: Open TCP connections in active mode
   + Bit 4: Open TCP connections in passive mode, with specified remote socket
   + Bit 5: Open TCP connections in passive mode, with unsepecified remote socket
   + Bit 6: Send and receive TCP urgent data
   + Bit 7: Explicitly set the PUSH * Bit when sending TCP data
   + Bit 8: Send data to a TCP connection before the ESTABLISHED state is reached
   + Bit 9: Discard data in the output buffer of a TCP connection
   + Bit 10: Open UDP connections
   + Bit 11: Open raw IP connections
   + Bit 12: Explicitly set the TTL and ToS for outgoing datagrams
   + Bit 13: Explicitly set the automatic reply to PINGs on or off
   + Bit 14: Automatically obtain the IP addresses, by using DHCP or an equivalent protocol (deprecated)
   + Bit 15: Get the TTL and ToS for outgoing datagrams
    
 * 2: Connection pool size and status

   + Success status code
   + One byte: Maximum TCP simultaneous connections supported
   + One byte: Maximum UDP simultaneous connections supported
   + One byte: Free connections currently available(TCP)
   + One byte: Same for UDP

 * 3: Maximum datagram size allowed

   + Success status code
   + Two bytes: Maximum incoming datagram size supported
   + Two bytes: Maximum outgoing datagram size supported

 * 4: Second capabilities word (UNAPI TCP/IP 1.1)

   + Success status code
   + Two bytes: second capabilities flags (bit 0: automatic local IP/mask/gateway, bit 1: automatic DNS, bits 8-9: TLS)
   + Two bytes: second features flags (always zero)

 * 5: Features flags and link level protocol (NiFi extension, firmware 0.2+)

   + Success status code
   + Two bytes: UNAPI features flags (bit 1: wireless, bit 10: DNS_Q is blocking, bit 11: TCP_OPEN is blocking)
   + One byte: link level protocol (4 = WiFi)

### 0x02 - Get IP address

Parameters:
 
 * Index of address to obtain

   + 1: Local IP address
   + 2: Peer IP address
   + 3: Subnet mask
   + 4: Default gateway
   + 5: Primary DNS server IP address
   + 6: Secondary DNS server IP address

Response:
  
  * Wrong address index - code 4(inv. parameter)

  * If not configured - success and four zeros

  * Other conditions: success and 4 bytes in lexical order(B0.B1.B2.B3) 

### 0x03 - Get network state

No input parametes.

Response:

 * Always success
 
 * One byte status:

  + 0: Closed

  + 1: Opening

  + 2: Open

  + 3: Closing

  + 255: Unknown

### 0x6 - Resolve host name

Parameters:

 * Zero-terminated domain name

Result:

 * Error code

 * If no error lexical order 4 bytes for IP.

### 0x8 - Open a UDP connection

Parameters:

 * Two bytes - port

Response:

 * Error code

 * If no error - connection number

### 0x9 - Close a UDP connection

Parameters:

 * One byte - connection number

Response:

 * Error code

### 0x0A - Get status for UDP connection

Parameters:

 * One byte - connection number

Response:

 * Error code

 * If no error:

  + Two bytes - local port

  + Two bytes - size of incoming data

### 0x0B - Send datagram 

Parameters:

 * One byte - connection number

 * Dest. ip address(4 bytes. lexical order)

 * Dest. port(2 bytes)

 * Data len(2 bytes)

 * Data block

Response:

 * Error code

### 0x0C - Receive datagram

Parameters:

 * One byte - connection number

 * Maximum size to receive

Response:

 * Error code. Next fields only if no error

 * Source IP(4 bytes lexical order)

 * Source port(2 bytes)

 * Data size(actual)

 * Data block

### 0x0D - Open a TCP connection (legacy, active mode only)

Kept for old clients. New clients should use 0x14.

Parameters:

 * Remote IP address(4 bytes lexical order)

 * Remote port(2 bytes)

Response:

 * Error code

 * IF NO ERROR HAPPENS: connection number

### 0x0E - Close a TCP connection

Parameters:

 * Connection number(if zero - close all connections)

Response:

 * Error code

### 0x14 - Open a TCP connection (UNAPI parameter block, firmware 0.2+)

Parameters (the UNAPI TCPIP_TCP_OPEN parameter block, 11 bytes):

 * Remote IP address (4 bytes, 0.0.0.0 = unspecified remote socket, passive mode only)

 * Remote port (2 bytes, ignored when the remote IP is unspecified)

 * Local port (2 bytes, 0xFFFF = random port between 16384 and 32767)

 * User timeout in seconds (2 bytes, 0 = default, 0xFFFF = "infinite", 1..1080 otherwise). Applied to the establishment of active connections

 * Flags (1 byte): bit 0 = passive (LISTEN), bit 1 = resident (not closed by "close all"), bit 2 = TLS, bit 3 = verify certificate. TLS is not supported (error 1)

Response:

 * Error code

 * If no error: connection number

 * If the error is 11 (connection does not exist, active open failed): close reason (see 0x13)

Active mode blocks until the connection is established or the timeout expires. Passive mode
returns immediately with the connection in LISTEN state; the connection turns ESTABLISHED when
a client arrives (it keeps the same connection number). Several passive connections may share
the same local port when their remote socket is unspecified. A passive connection with a
specified remote socket only accepts that peer; other clients are reset.

Errors: 4 (bad flags, bad timeout, active open without remote IP), 2 (no WiFi), 10 (same
local port / remote socket already in use), 9 (no free connection).

### 0x15 - Abort a TCP connection

Parameters:

 * Connection number (if zero - abort all transient connections)

Response:

 * Error code

The connection is dropped at once, sending RST when it was established.

### 0x10 - Get the state of a TCP connection (legacy)

Parameters:

 * Connection number

Result:

 * Error code

 * Connection state:

   + 0: Unknown

   + 1: LISTEN

   + 2: SYN-SENT

   + 3: SYN-RECEIVED

   + 4: ESTABLISHED

   + 5: FIN-WAIT-1

   + 6: FIN-WAIT-2

   + 7: CLOSE-WAIT

   + 8: CLOSING

   + 9: LAST-ACK

   + 10: TIME-WAIT

 * Two bytes - total available bytes

### 0x13 - Get the extended state of a TCP connection (firmware 0.2+)

Everything the UNAPI TCPIP_TCP_STATE function needs in a single exchange.

Parameters:

 * Connection number

Response:

 * Error code 11 (connection does not exist or is closed), followed by one byte with the close reason:

   + 0: Unknown
   + 1: The connection was never used
   + 2: Closed locally (0x0E)
   + 3: Aborted locally (0x15)
   + 4: RST received (the remote host refused or reset the connection)
   + 5: User timeout
   + 6: Establishment timeout
   + 7: Network lost
   + 8: Destination unreachable

 * Error code 0, followed by:

   + Remote IP address (4 bytes; the expected peer while listening)
   + Remote port (2 bytes)
   + Local port (2 bytes)
   + Connection state (1 byte, same values as 0x10)
   + Flags (1 byte, always 0: no TLS)
   + Two bytes - total available bytes

### 0x11 - Send data a TCP connection

Parameters:

 * Connection number

 * Data length

 * Data block

Response:

 * Error code

### 0x12 - Receive data from a TCP connection

Parameters:
  
  * Connection number

  * Length of the data to be obtained

Response:

  * Error code. If error happens only error code will be sent.

  * 2 bytes data length

  * Data block


### 0x30 - Get WiFi AP list

No parameters

Response:

 * Error code

 * List of Zero-terminated strings(list ends with 0xff byte) - AP names

### 0x31 - Connect to AP

Parameters:

 * Zero-terminated string - access point name

 * Zero-terminated string - password(if absent send empty string)

Response:

 * Error code

### 0x32 - Get Current AP

No parameters.

Response:

 * Error code
 
 * If no error - zero-terminated string
 
### 0x33 - Get signal strength (firmware 0.2+)

No parameters.

Response:

 * Error code (2 when not connected)

 * One byte: RSSI of the current access point in dBm (signed)

### 0x34 - Get MAC address (firmware 0.2+)

No parameters.

Response:

 * Error code (always success)

 * Six bytes: station MAC address

### 0x35 - Forget access point (firmware 0.2+)

Disconnects and erases the credentials stored in flash.

No parameters.

Response:

 * Error code (always success)

### 0x36 - Get WiFi AP list with details (firmware 0.2+)

No parameters.

Response:

 * Error code (2 when no network was found)

 * One entry per network, strongest signal first (list ends with 0xff byte):

   + Zero-terminated string - AP name
   + One byte - RSSI in dBm (signed)
   + One byte - 0 = open network, 1 = password required

### 0x40 - 0x47 - ROM loader (firmware 0.3+)

Used by the NETROM utility to browse HTTP(S) directory listings and download
files. The modem does all the heavy work: TLS, redirects, chunked transfers,
HTML parsing and DEFLATE. Downloads are stored in the modem flash (LittleFS),
so the firmware must be built with a file system partition.

Listings are parsed from the HTML of the server (Apache style indexes,
file-hunter, archive.org `/download/` pages and the archive.org zip content
viewer). Every link becomes an entry with a flags byte (bit 0 = directory), a
size (the last size-looking token after the link in the same row, 0 when
unknown) and a display name (ASCII, 79 characters at most). Links with a query
string, to other hosts or to the parent directory are ignored.

All these commands block until the operation is complete (a listing or a
download may take from a few seconds to a minute).

#### 0x40 - List an URL

Parameters:

 * Zero-terminated URL (http:// or https://, spaces are encoded by the modem)

Response:

 * Error code (17 + status on HTTP errors, 4 for a malformed URL)

 * If no error: two bytes - number of entries. The URL becomes the current location.

#### 0x41 - Get a page of the current listing

Parameters:

 * Two bytes - first matching entry to return (0 based)

 * One byte - number of entries wanted (32 at most)

 * Zero-terminated filter: only entries whose name contains it (case insensitive) are returned; empty = all

Response:

 * Error code (15 when there is no current listing)

 * Two bytes - total number of matching entries

 * One byte - number of entries that follow

 * For each entry: two bytes index (position in the listing, used by 0x42 and 0x44),
   one byte flags (bit 0 = directory), four bytes size, zero-terminated name

#### 0x42 - Enter a directory entry

Parameters:

 * Two bytes - index of a directory entry

Response: as 0x40. The current location becomes that directory.

#### 0x43 - Go to the parent directory

No parameters. Response: as 0x40 (error 15 at the root of the host).

#### 0x44 - Download a file entry

Parameters:

 * Two bytes - index of a file entry of the current listing

Response:

 * Error code (17 + status, 14 when the file does not fit in the flash,
   18 for a bad zip, 19 for a flash error)

 * If no error: four bytes size, four bytes CRC-32, zero-terminated file name

When the downloaded file is a zip, the first entry with a ROM-like extension
(.rom .mx1 .mx2 .bin .sg .col), or the first file when there is none, is
extracted and its CRC-32 is verified. Other files are kept as they are. The
name returned is the name of the extracted file (or the listing name).

#### 0x45 - Download an URL

Parameters:

 * Zero-terminated URL

Response: as 0x44.

#### 0x46 - Read a block of the downloaded file

Parameters:

 * Four bytes - offset

 * Two bytes - length (1300 at most)

Response:

 * Error code (3 when no file was downloaded)

 * Two bytes - length actually read (0 past the end of the file)

 * Data

#### 0x47 - Current location

No parameters.

Response:

 * Error code (always success)

 * Zero-terminated URL of the current listing (empty when none, 255 characters at most)

### 0x50 - 0x52 - Firmware update over the air (firmware 0.3+)

The modem can replace its own firmware with an image downloaded by HTTP or HTTPS
(ESP8266httpUpdate: the image is written to the free OTA slot and only becomes active
when it was written completely, so a failed transfer keeps the old firmware). The sketch
must be built with a "Flash Size" that leaves room for OTA.

A repository is just a directory on a web server with `nifi.bin` (the compiled sketch,
"Export compiled binary" in the Arduino IDE) and `version.txt` (first line = version).

#### 0x50 - Read a short text file

Parameters:

 * Zero-terminated URL (for example `.../version.txt`)

Response:

 * Error code (17 + status on HTTP errors)

 * If no error: zero-terminated first line of the file (63 characters at most)

#### 0x51 - Update the firmware

Parameters:

 * Zero-terminated URL of the firmware image

Response:

 * Error code: 0 when the image was written (the modem reboots right after sending it:
   the host must send 0x00 again and wait for "NiFi"), 2 without network, 4 for a bad
   URL, 20 followed by a zero-terminated description when the update failed (too little
   space, bad image, HTTP error, ...). All TCP/UDP connections are closed first.

#### 0x52 - Flash information

No parameters.

Response:

 * Error code (always success)

 * Four bytes - flash chip size

 * Four bytes - size of the running sketch

 * Four bytes - free space for an OTA image (the new image must be smaller)

 * Zero-terminated running version (e.g. "0.3")

#### 0x53 - 0x56 - Firmware update from the host

The image is sent by the host (NIFICFG reads it from a DOS file) and written to the
spare OTA slot by the modem; it only becomes active after 0x55 succeeds.

 * 0x53: four bytes - image size. Response: error (20 + description when the image does
   not fit the free OTA space)

 * 0x54: two bytes - block length (1300 at most), then the data. Response: error
   (15 when no update was started, 4 when more data than announced arrives, 20 + text
   on a flash error). The modem writes the data before answering, so the host must wait
   for the answer before sending the next block

 * 0x55: no parameters. Response: error; 0 means the image is complete and verified,
   the modem reboots right after answering

 * 0x56: no parameters. Discards a partial image. Response: error (always 0)

### 0xFF - Get build information

No parameters.

Response:

 * Error code(always success)
 
 * Zero-terminated string containing version and build time

---

Copyright (C) 2026 Andrés Ortiz. Licensed under the GNU General Public License v3 or later.
Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander Sharihin), Copyright (C) 2021,
and on work by Ducasp (Oduvaldo Pavan Junior), Copyright (C) 2020. See the Credits section of the README.
