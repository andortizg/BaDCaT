# NiFi for MSX - technical manual

NiFi turns an ESP8266 module connected to a 16C550 UART cartridge (BadCat and
compatibles) into a hardware TCP/IP stack for the MSX. This manual covers the
firmware 0.3, the UNAPI driver 1.1 and the two MSX-DOS utilities, NIFICFG and
NETROM: how they work, how to build them, how to install the firmware and how
to use the tools.

Contents

1. [Overview](#1-overview)
2. [How it works](#2-how-it-works)
3. [Building](#3-building)
4. [Installing the firmware](#4-installing-the-firmware)
5. [Installing on the MSX](#5-installing-on-the-msx)
6. [NIFICFG - WiFi configuration and firmware updates](#6-nificfg)
7. [NETROM - loading ROMs from the internet](#7-netrom)
8. [The UNAPI driver](#8-the-unapi-driver)
9. [Testing from a PC](#9-testing-from-a-pc)
10. [Limitations and troubleshooting](#10-limitations-and-troubleshooting)

---

## 1. Overview

```
 MSX                       BadCat cartridge                 ESP8266 (NiFi firmware)
 +------------------+      +-------------------+            +---------------------+
 | UNAPI apps       |      |                   |  TX/RX     | WiFi station        |
 | NIFICFG / NETROM |<---->| 16C550(C) at #80  |<---------->| TCP/UDP/DNS (lwIP)  |
 | nifi.com driver  | I/O  | (FIFO, RTS/CTS)   |  RTS/CTS   | HTTP(S) downloads   |
 +------------------+      +-------------------+  115200 8N1| zip inflate, OTA    |
                                                            | LittleFS            |
                                                            +---------------------+
```

The MSX talks to the modem with a small binary request/response protocol over the
UART (one command byte, parameters, then an error byte and the result). All the
network work happens on the ESP8266: the MSX side only moves bytes.

| Component | Path | Purpose |
|-----------|------|---------|
| Firmware 0.3 | `Nifi/` | Arduino sketch for the ESP8266: WiFi, TCP active and passive, UDP, DNS, HTTP(S) downloads with zip extraction, directory listings, OTA updates |
| UNAPI driver 1.1 | `msx/unapi-driver/nifi/` | `nifi.com`, the TCP/IP UNAPI 1.1 implementation used by MSX network applications |
| NIFICFG | `msx/nificfg/` | `nificfg.com`, WiFi configuration, modem information and firmware updates |
| NETROM | `msx/netrom/` | `netrom.com`, browse ROM repositories on the internet, download, save or run |
| Protocol reference | `wifi-modem-description.md` | Every command byte, parameter and response |
| PC testers | `tester/` | Python scripts that drive the modem from a PC serial port, and a test for the DEFLATE decoder |

---

## 2. How it works

### 2.1 The UART link

The cartridge maps a 16C550 UART at I/O ports `#80`-`#87` (`UART_BASE` in
`driver/uart.asm`). The link runs at 115200 bps, 8N1, with hardware FIFOs.

Two flavours of the cartridge exist:

* **16C550C**: the chip has *automatic flow control* (AFE). RTS drops by itself when
  the receive FIFO reaches the trigger level and the transmitter stops when CTS is
  inactive. The MSX software does not have to care about timing.
* **16C550** (no AFE): the same chip without the automatic mode. Flow control has
  to be done by software.

The shared `driver/uart.asm` module (identical copies in the driver, NIFICFG and
NETROM) identifies the chip when it initialises:

1. scratch register test (`#87`): write two values and read them back; no answer
   means no UART;
2. FIFO test: enable the FIFO and check bits 7-6 of the IIR;
3. AFE test: try to set bit 5 of the MCR; only a 16C550C/16C750 keeps it.

With AFE the module programs `MCR = #2F` and the hardware does the rest. Without it
the module mirrors what the modem does on its own side:

* **receiving**: RTS is raised only while a read routine waits for a byte and
  dropped as soon as the byte arrives. The modem checks CTS before *every* byte it
  sends and never has more than one byte in flight, so at most one extra byte can be
  in the FIFO while the MSX is busy with an interrupt or a disk access. Nothing is
  lost and no interrupt hook is needed;
* **sending**: before each byte the module waits for CTS (MSR bit 4), with a timeout
  of about one second in case the line is not wired.

The price of the software mode is a lower throughput (roughly 5 KB/s instead of
10 KB/s) because of the RTS round trip per byte.

### 2.2 The protocol

Every exchange is initiated by the MSX: one command byte, its parameters, and the
modem answers with an error byte (0 = success) followed by the result. Strings are
zero terminated, multi-byte values are little endian, IP addresses are four bytes.
The modem never sends anything on its own, which is what makes the simple flow
control above safe.

The error codes 0-16 are the UNAPI TCP/IP ones; 17-20 are NiFi additions (HTTP
error with status, bad archive, flash storage error, update failed).

Command groups (see `wifi-modem-description.md` for the details):

| Range | Group |
|-------|-------|
| `00`-`03` | reset, capabilities, IP addresses, network state |
| `06` | DNS |
| `08`-`0C` | UDP |
| `0D`-`15` | TCP (open legacy / open with the UNAPI parameter block, close, abort, state, send, receive) |
| `30`-`36` | WiFi: scan, connect, current AP, RSSI, MAC, forget |
| `40`-`47` | ROM loader: listings, downloads, file blocks |
| `50`-`56` | firmware update: over the air and from the host |
| `FF` | build information |

### 2.3 Firmware internals

The sketch is split in modules (`.ino` files are concatenated by the Arduino IDE,
`Nifi.ino` first):

* `exchange.*` - UART I/O. `get_byte()` raises RTS, waits for a byte and drops RTS;
  `publish_byte()` checks CTS, sends one byte and waits until it is on the wire.
  While the modem waits for the next byte from the host it polls the TCP listeners,
  which is the only moment it can accept incoming connections (the host drives the
  exchange, so there is no other idle loop).
* `protocol.*` - command codes, error codes, capability flags and the dispatcher.
* `tcp_slot.h` / `connection_manager.ino` - one *slot* per UNAPI connection number
  (`MAX_SOCKETS`, 8). A slot holds a `WiFiClient`, its state (listening, resident,
  close reason, expected remote socket, local port). Listeners (`WiFiServer`) are
  shared by local port with a reference count, so several passive connections may
  listen on the same port as the UNAPI specification requires. Connection states and
  close reasons use the UNAPI numbering (identical to lwIP's).
* `network.ino` - TCP state/send/receive, UDP, DNS.
* `netman.ino` - WiFi management. Credentials are stored by the SDK in flash, so the
  modem reconnects by itself after power on.
* `romloader.*` - HTTP(S) client with manual redirects (the scheme may change between
  hops), HTML directory listing parser, zip extraction and the two kinds of firmware
  update.
* `inflate.*` - a small streaming DEFLATE decoder (RFC 1951, puff style) with a 32 KB
  window and a CRC-32 helper. No Arduino dependencies, testable on a PC.

**Downloads work in two phases** because the ESP8266 has about 40 KB of free heap:
the TLS client needs 16 KB of buffers plus the handshake memory, and the inflate
window needs 32 KB. The compressed file is first written to the LittleFS partition,
the TLS connection is closed, and only then the zip entry is inflated flash to flash.
The CRC-32 stored in the zip is verified, which also covers the fact that TLS
certificates are not validated (the modem has no clock nor trust store).

**Directory listings** are parsed in a streaming way: every `<a href>` becomes an
entry (directory when the link ends with `/`), the display name is the link text,
and the size is the last size-looking token (`16384`, `17.76 KB`, `26.5M`) found in
the row after the link, ignoring dates and times. Links with a query string, to other
hosts or to the parent directory are skipped. The entries are stored in flash
(`/list.bin`) and served to the MSX page by page, with an optional case-insensitive
filter, so even an 800 KB index is browsed comfortably from the MSX.

**OTA updates** use the core's `ESP8266httpUpdate` (image fetched by the modem) or
the `Update` class (image sent by the host). Either way the image is written to the
spare program slot and only activated when complete, so a failed transfer keeps the
running firmware.

### 2.4 Running a ROM from RAM (NETROM)

A cartridge lives in its own slot at `4000h`-`BFFFh`. Under MSX-DOS pages 1 and 2
are RAM, and a soft reset does not clear them. NETROM copies the image there (at
`4000h`, or at `8000h` for 8/16 KB images whose INIT or TEXT address points to page
2), then resets the machine through the BIOS entry at `0000h`. The BIOS scans every
slot for the `AB` signature at boot, finds it in the RAM slot and starts the
"cartridge" as if it were plugged in. `romboot.asm` takes care of pointing page 0 to
the main ROM, including the secondary slot register when primary slot 0 is expanded.

This classic trick covers plain 8, 16 and 32 KB cartridges. MegaROMs (Konami, ASCII
8/16 mappers), 48/64 KB images that use page 0 and games that check that they run
from real ROM need a device with mapper emulation (MegaFlashROM SCC+ SD, Carnivore2,
MegaRAM, GR8NET): save the file and use SofaRun or a similar loader.

---

## 3. Building

### 3.1 Firmware

Requirements: Arduino IDE (or arduino-cli) with the **ESP8266 core 3.x** installed
from the Boards Manager (`http://arduino.esp8266.com/stable/package_esp8266com_index.json`).
No extra library is needed: `ESP8266WiFi`, `ESP8266HTTPClient`, `WiFiClientSecure`,
`LittleFS`, `ESP8266httpUpdate` and `Updater` are part of the core.

1. Open `Nifi/Nifi.ino`.
2. Board: your module (for example "Generic ESP8266 Module" or "NodeMCU 1.0").
3. **Flash Size**: choose a layout **with a file system and OTA space**. For a 4 MB
   module use `4MB (FS:2MB OTA:~1019KB)`; for a 1 MB module use `1MB (FS:256KB
   OTA:~374KB)` and lower `MAX_ROM_DOWNLOAD` in `configuration.h`. Without a file
   system the ROM loader answers error 19 and OTA is impossible.
4. Check `configuration.h`: baud rate (115200), flow control pins (`CTS_PIN` 5,
   `RTS_PIN` 4, seen from the computer side: connect CTS to CTS and RTS to RTS),
   `MAX_SOCKETS`, `HTTP_USER_AGENT`.
5. Verify / Upload.

To produce an image for OTA updates use *Sketch > Export compiled binary* and rename
the result to `nifi.bin`.

Optional PC check of the DEFLATE decoder (any C++ compiler, no Arduino needed):

```
g++ -O2 -o inflate_test tester/inflate_test.cpp Nifi/inflate.cpp
./inflate_test some.zip
```

### 3.2 MSX driver and tools

Requirements: [sjasmplus](https://github.com/z00m128/sjasmplus) 1.18 or later. Run it
inside each folder (the includes are relative):

```
cd msx/unapi-driver/nifi
sjasmplus nifi.asm          -> nifi.com

cd msx/nificfg
sjasmplus main.asm          -> nificfg.com

cd msx/netrom
sjasmplus main.asm          -> netrom.com
```

If your cartridge maps the UART elsewhere, change `UART_BASE` in `driver/uart.asm` of
each tool (the three copies must stay identical).

---

## 4. Installing the firmware

### 4.1 First time: serial upload

Connect the ESP8266 to a PC with a USB-serial adapter (or the cartridge's programming
header), put the module in flash mode (GPIO0 low at reset) and upload from the Arduino
IDE. The module keeps nothing from previous firmware: WiFi credentials have to be
entered again with NIFICFG.

### 4.2 Updates over the air (NIFICFG option 6)

Publish two files in a plain HTTP(S) directory:

* `nifi.bin` - the exported binary, built for the same flash size as the module;
* `version.txt` - the version on its first line (for example `0.3`).

A GitHub release works as well: attach both files and use
`https://github.com/<user>/<repo>/releases/latest/download/` as repository URL (the
modem follows redirects).

Put the URL in `NIFICFG.CFG` next to `nificfg.com`:

```
UPDATE=https://host/path/
```

Then run NIFICFG, option 6 (or `NIFICFG /U`). The tool shows the installed and the
published versions and the free OTA space, asks for confirmation, and the modem
downloads and flashes the image. After the reboot NIFICFG looks for the modem again
and prints the new version.

### 4.3 Updates from a file (NIFICFG option 7)

Copy `nifi.bin` to any DOS device (floppy, MegaFlashROM SD, Carnivore2, Nextor
partition...) and run NIFICFG option 7 or `NIFICFG /B [file]` (`NIFI.BIN` by
default). The image goes to the modem in 1 KB blocks, about one minute for a typical
image, and is activated only when complete.

If the modem does not answer after an update, switch the computer off and on: the
module reboots on power up with whichever image was active.

---

## 5. Installing on the MSX

Copy `nifi.com`, `nificfg.com`, `netrom.com`, `NIFICFG.CFG` and `NETROM.CFG` to a
DOS disk, together with `ramhelpr.com` (the UNAPI RAM helper, from Konamiman's UNAPI
package). The driver needs MSX-DOS 2 or Nextor with a memory mapper; NIFICFG and
NETROM also work on MSX-DOS 1.

1. `NIFICFG` - connect to your WiFi network once (option 2). The modem stores the
   credentials.
2. `RAMHELPR I` - install the RAM helper.
3. `NIFI` - install the driver.

A typical `AUTOEXEC.BAT`:

```
RAMHELPR I
NIFI
```

The driver prints the UART type it found. With no UART at the port, or when the modem
does not answer within about ten seconds, it restores the hooks and exits with an
error instead of hanging.

---

## 6. NIFICFG

```
NIFICFG                 interactive menu
NIFICFG /S              show network status
NIFICFG /L              list the access points
NIFICFG /C ssid [pass]  connect (for AUTOEXEC.BAT)
NIFICFG /F              forget the stored network
NIFICFG /U              update the firmware from the configured repository
NIFICFG /B [file]       update the firmware from a file (NIFI.BIN)
NIFICFG /?              help
```

At start the tool identifies the UART (and warns when it is a plain 16C550 or none
is found), resets the modem and shows a one line summary: network, IP and signal.

Menu:

1. **Network status** - firmware version, MAC, link state, SSID, signal in dBm with a
   gauge, IP, netmask, gateway, DNS servers.
2. **Scan and connect** - numbered list of networks sorted by signal, `*` marks the
   ones that need a password. Pick a number, type the password (shown as asterisks,
   ESC cancels). The modem associates, gets an address by DHCP and stores the
   credentials for the next power on.
3. **Connect typing the name** - for hidden networks.
4. **Forget the stored network** - disconnects and erases the credentials.
5. **Modem information** - firmware build, MAC, UART type and port.
6. **Update the firmware from the internet** - see 4.2.
7. **Update the firmware from a file** - see 4.3.

Names and passwords with spaces go between double quotes on the command line.
MSX-DOS 1 converts the command line to upper case: use the menu for case sensitive
names and passwords.

`NIFICFG.CFG` (optional, `#` starts a comment):

```
UPDATE=https://host/path/
```

---

## 7. NETROM

```
NETROM                  interactive: repositories, browse, download
NETROM url/             browse a directory listing
NETROM url              download one file
NETROM /?               help
```

NETROM needs firmware 0.3 and a modem already connected to a network.

### 7.1 Repositories

`NETROM.CFG` lists up to nine repositories, one per line, `Name=URL` where the URL is
a directory listing (ending with `/`):

```
file-hunter - MSX1 ROM=https://download.file-hunter.com/Games/MSX1/ROM/
file-hunter - MSX2 ROM=https://download.file-hunter.com/Games/MSX2/ROM/
TOSEC - MSX Games [ROM]=https://archive.org/download/TOSEC_2020_Roundup/MSX/MSX/Games/%5BROM%5D/MSX%20MSX%20-%20Games%20-%20%5BROM%5D%20%28TOSEC-v2012-04-15%29.zip/
TOSEC - MSX (browse all)=https://archive.org/download/TOSEC_2020_Roundup/MSX/
```

Without the file a built-in list with these entries is used. Any server that shows an
HTML directory index works (Apache/nginx indexes, file-hunter, archive.org `download`
pages). On archive.org a zip can be browsed as a directory by adding `/` to its URL:
the server extracts the files itself, so TOSEC packs are usable without downloading
the whole pack.

### 7.2 Browsing

The repository menu shows the configured entries, `U` to type an URL and `Q` to quit.
Inside a listing the screen shows the location, a page of 20 entries (`<DIR>` or the
size in KB, then the name) and a prompt:

| Key | Action |
|-----|--------|
| number + Enter | open the directory / download the file |
| `N` or empty line | next page |
| `P` | previous page |
| `F` | filter: show only the names containing some text (the filter runs on the modem) |
| `U` | parent directory |
| `R` | back to the repository list |
| `H` | help |
| `Q` | quit |

### 7.3 Downloading, saving and running

When a file is selected the modem fetches it (HTTPS, redirects and zip extraction
included; the first entry with a ROM-like extension is taken from a zip) and NETROM
shows the name and size, then asks:

* **R - Run from RAM**: for plain cartridge images of 8/16/32 KB with the `AB` header
  at the start. The image is copied to RAM and the machine resets into it (see 2.4).
  Larger images or files without the signature are refused with an explanation.
* **S - Save to disk**: a DOS file name is proposed from the ROM name (`XXXXXXXX.ROM`),
  edit it or press Enter. The file is received in 1 KB blocks with a progress counter;
  ESC cancels.
* **B - Both**: save, then run.

Transfers run at about 10 KB/s (5 KB/s on a cartridge without AFE): a 32 KB ROM takes
a few seconds, a 512 KB MegaROM about a minute.

---

## 8. The UNAPI driver

`nifi.com` implements the TCP/IP UNAPI specification 1.1 (identifier `TCP/IP`) with
everything the hardware can support:

* `TCPIP_GET_CAPAB` blocks 1-4: DNS, active TCP, passive TCP with specified and
  unspecified remote socket, UDP, DHCP; features "wireless", "DNS_Q is blocking",
  "TCP_OPEN is blocking"; link level protocol WiFi.
* `TCPIP_TCP_OPEN` with the full parameter block: remote IP and port, local port
  (`#FFFF` = random), user timeout, flags passive / resident. Active opens block until
  the connection is established or the timeout expires. Passive opens return at once
  with the connection in LISTEN state; it becomes ESTABLISHED when a client arrives
  and keeps the same connection number. Several passive connections may share a local
  port; a passive connection with a specified remote socket only accepts that peer.
* `TCPIP_TCP_CLOSE` (graceful, `B = 0` closes all transient connections),
  `TCPIP_TCP_ABORT` (RST), `TCPIP_TCP_STATE` (information block, state, flags, close
  reason when the connection no longer exists, available bytes), `TCPIP_TCP_SEND`,
  `TCPIP_TCP_RCV`.
* UDP open/close/state/send/receive, `TCPIP_DNS_Q` / `TCPIP_DNS_S`, IP addresses,
  network state.

Not implemented: TLS, urgent data, PUSH flag control, `TCPIP_TCP_DISCARD`, raw IP,
ICMP echo. The driver needs firmware 0.2 or later.

Applications that work as servers (telnet or HTTP servers, file transfer tools in
passive mode) behave as they do with ObsoNET or GR8NET.

---

## 9. Testing from a PC

The `tester/` scripts need Python 3 with `pyserial` and the ESP8266 connected to a
PC serial port (use the module's own UART pins; the scripts assume no hardware flow
control, so leave CTS/RTS unconnected or tie the ESP's CTS input active).

| Script | Purpose |
|--------|---------|
| `tester.py` | WiFi, DNS and active TCP commands |
| `tester_passive.py COM3` | opens a listening connection on port 2323 and echoes everything (connect with `nc <modem ip> 2323`) |
| `tester_rom.py COM3 list <url> [filter]` | prints a directory listing as the modem parses it |
| `tester_rom.py COM3 get <url> <file>` | downloads an URL (zips are unpacked), transfers it, verifies the CRC-32 and saves it |
| `inflate_test.cpp` | PC test of the DEFLATE decoder against any zip file |

---

## 10. Limitations and troubleshooting

* **TLS certificates are not verified**. The integrity of zip downloads is checked
  with the archive CRC-32; firmware images are checked by the ESP updater.
* **Downloads are limited by the free flash** (`MAX_ROM_DOWNLOAD`, 2 MB by default)
  and need about 25 KB of free heap for TLS.
* **file-hunter** refuses clients without a browser-like User-Agent and asks not to
  use download managers. The modem identifies itself as
  `Mozilla/5.0 (compatible; NiFi-MSX/0.3; ESP8266)` (`HTTP_USER_AGENT`); if the site
  answers HTTP 405, adjust it. Browse at a human pace.
* **CLOSE-WAIT**: when the remote host closes a connection with no pending data the
  ESP8266 core releases it at once, so the connection goes straight to "closed"
  instead of passing through CLOSE-WAIT. Applications usually test both.
* **"The modem does not answer"**: check that the ESP has the NiFi firmware and the
  baud rate matches, that the UART is at `#80` (NIFICFG option 5 shows what was
  found), and the RTS/CTS wiring. On a 16C550 without AFE the tools print a notice and
  switch to software flow control.
* **Error 19 (flash)**: the firmware was built without a LittleFS partition, or the
  partition is full. Rebuild with a "Flash Size" that includes a file system.
* **OTA fails with "not enough space"**: the sketch must fit in half of the program
  space; use a layout with more OTA room or a bigger module.
* **A ROM does not start from RAM**: it probably needs a mapper, page 0 or real ROM.
  Save it and use SofaRun with a MegaFlashROM/Carnivore2.

---

Copyright (C) 2026 Andrés Ortiz. Licensed under the GNU General Public License v3 or later.
Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander Sharihin), Copyright (C) 2021,
and on work by Ducasp (Oduvaldo Pavan Junior), Copyright (C) 2020. See the Credits section of the README.
