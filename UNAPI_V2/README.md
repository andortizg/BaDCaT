# NiFi UNAPI V2 - ESP8266 firmware, UNAPI driver and tools for the BadCat MSX cartridge

Firmware for using as hardware TCP/IP stack for retrocomputers and your hobby projects.

This repository is a fork of [nihirash/esp-binary-firmware](https://github.com/nihirash/esp-binary-firmware)
by Nihirash (Alexander Sharihin). It adds passive (server) TCP connections and the full UNAPI TCP/IP
1.1 TCP functions to the firmware and the MSX driver, a friendly configuration utility
(NIFICFG) with over-the-air and from-disk firmware updates, a ROM loader that browses
internet repositories (NETROM), and support for both the 16C550C (AFE) and the plain
16C550 versions of the BadCat cartridge.

Maintained by Andrés Ortiz. See [Credits](#credits) for everyone whose work this version builds on.

See [MANUAL.md](MANUAL.md) for the technical manual: how it works, building, installing
the firmware and using the tools.

## Features

 * Active TCP connections (client)
 * Passive TCP connections (server / LISTEN), with specified or unspecified remote socket,
   several listeners on the same local port, local port selection and user timeout
 * Graceful close and abort (RST), full UNAPI connection states and close reasons
 * UDP
 * DNS resolution, DHCP
 * WiFi management: scan with signal strength and encryption, connect, forget, RSSI, MAC
 * Firmware update over the air from an HTTP(S) repository (NIFICFG menu)
 * Credentials are stored in the ESP flash: the modem reconnects by itself at power on
 * ROM loader: browse HTTP(S) directory listings (file-hunter, archive.org TOSEC, any
   Apache style index), download a file to the modem flash, unpack it when it is a zip and
   hand it to the computer in blocks (used by the NETROM utility)

## Building

Use Arduino for building project (ESP8266 core 3.x is required: the passive TCP code
uses `WiFiServer::accept()` / `begin(port, backlog)`).

`Nifi.ino` is main project file. `configuration.h` contains all configuration(you can change baudrate, enable/disable flow control and change pins for it).

The ROM loader stores downloads in a LittleFS partition, so pick a "Flash Size" with a
file system in the Arduino IDE (for a 4 MB module "4MB (FS:2MB OTA:~1019KB)"; with a
1 MB module use "1MB (FS:256KB)" and lower `MAX_ROM_DOWNLOAD` in `configuration.h`).
Downloads need about 25 KB of free heap for TLS: the default sketch leaves enough, but
keep that in mind if you add features.

CTS and RTS pins marked from computer side(connect CTS to CTS and RTS to RTS).

### Firmware layout

 * `protocol.h` / `protocol.ino` - command codes, error codes, capability flags and the command dispatcher
 * `exchange.*` - UART exchange with flow control. While the modem waits for the next byte
   from the host it hands incoming connections to the passive slots
 * `tcp_slot.h` / `connection_manager.ino` - connection slots (one per UNAPI connection number),
   listeners shared by local port, open / close / abort
 * `network.ino` - TCP state, send and receive, UDP, DNS
 * `netman.ino` - WiFi management
 * `romloader.*` - HTTP(S) downloads to flash, zip extraction, directory listings (commands 0x40-0x47) and OTA update (0x50-0x52)
 * `inflate.*` - small streaming DEFLATE decoder and CRC-32 (no Arduino dependencies, see `tester/inflate_test.cpp`)

## MSX2 UnApi driver

Yes, it can be used with MSX computers. I've made UnApi driver for BadCat cartridge(that contains 16C550 chip that have autoflow control feature).

For building driver you'll need [sjasmplus from z00m128](https://github.com/z00m128/sjasmplus).

Just execute it on source file and get binary.

 * `msx/nificfg/main.asm` -> `nificfg.com` - WiFi configuration utility (menu driven, see below)
 * `msx/unapi-driver/nifi/nifi.asm` -> `nifi.com` - UNAPI TCP/IP driver (v1.1)
 * `msx/netrom/main.asm` -> `netrom.com` - ROM loader: browse internet repositories, download, save or run (see below)
 * `msx/wificonfig/main.asm` -> `iwconfig.com` - the original minimal configuration tool (kept for reference)

To use device: run `nificfg` once and connect to your access point (the modem remembers it),
then run `ramhelpr` and `nifi` (from AUTOEXEC.BAT, for example).

The driver v1.1 implements the whole TCP part of the UNAPI TCP/IP 1.1 specification that the
hardware can support: TCPIP_TCP_OPEN (active and passive, with the full parameter block),
TCPIP_TCP_CLOSE, TCPIP_TCP_ABORT, TCPIP_TCP_STATE (connection information block, state,
close reason, available bytes), TCPIP_TCP_SEND, TCPIP_TCP_RCV, plus UDP, DNS and the
capability / features / link protocol blocks. Programs that need a listening socket (telnet
or HTTP servers, file transfer tools working in passive mode, etc.) now work like they do
with ObsoNET or GR8NET.

The driver v1.1 needs firmware 0.2 or later (the extended status command changed).

### NIFICFG - configuration utility

```
NIFICFG                 interactive menu
NIFICFG /S              show network status (SSID, signal, IP, mask, gateway, DNS)
NIFICFG /L              scan and list the access points
NIFICFG /C ssid [pass]  connect to a network (for AUTOEXEC.BAT)
NIFICFG /F              forget the stored network and disconnect
NIFICFG /?              help
```

The interactive mode shows a numbered list of networks sorted by signal strength, with a
signal gauge and a `*` mark for networks that need a password. Pick a number, type the
password (shown as asterisks, ESC cancels) and the modem connects and stores the credentials.
Names and passwords with spaces go between double quotes on the command line. MSX-DOS 1
converts the command line to upper case, so use the menu for case sensitive names there.

Both flavours of the BadCat UART are supported: the 16C550C, whose automatic flow
control (AFE) drives RTS/CTS in hardware, and the plain 16C550, for which the shared
UART module (`driver/uart.asm`, identical in the driver, NIFICFG and NETROM) does the
flow control by software: it raises RTS only while it waits for a byte and checks CTS
before sending one, mirroring what the modem does, so nothing is lost even when the
MSX is busy with interrupts or disk access. The chip is identified at start (scratch
register, FIFO and AFE tests); NIFICFG shows the result in "Modem information" and the
driver prints a note when it falls back to software flow control. Without any UART at
the port the driver refuses to install instead of hanging.

Menu option 6 (or `NIFICFG /U`) updates the modem firmware over the air. Put the
repository URL in `NIFICFG.CFG` (`UPDATE=https://host/path/`, sample in `msx/nificfg/`):
the directory must contain `nifi.bin` (the compiled sketch, "Sketch > Export compiled
binary" in the Arduino IDE, built for the same flash size as the module) and
`version.txt` with the published version on its first line. NIFICFG shows the installed
and the published versions and the free OTA space, asks for confirmation, flashes the
image (the modem writes it to its spare slot, so a failed download does not break the
current firmware) and looks for the modem again after the reboot. A GitHub release
works as repository too: `https://github.com/<user>/<repo>/releases/latest/download/`
with both files attached to the release.

Option 7 (or `NIFICFG /B [file]`) flashes the modem from an image on any DOS device
(floppy, MegaFlashROM SD, Carnivore2, ...): `NIFI.BIN` by default. The file is sent in
1 KB blocks (about a minute for a typical image) and the modem activates it only when
the whole image has arrived, so an interrupted transfer keeps the old firmware.

If your cartridge maps the 16C550 at another I/O port, change `UART_BASE` in
`driver/uart.asm` of each tool.

### NETROM - load ROMs from the internet

```
NETROM                  interactive: repositories, browse, download
NETROM url/             browse a directory listing
NETROM url              download one file
NETROM /?               help
```

NETROM needs firmware 0.3 or later. It shows the repositories from `NETROM.CFG` (one
`Name=URL` per line, a sample is in `msx/netrom/`; without the file a built-in list with
file-hunter and the archive.org TOSEC set is used), then a paged listing of the chosen
directory: type a number to open a directory or download a file, `N`/`P` for the next and
previous page, `F` to show only the names containing some text (the filter runs on the
modem, so even the 800 KB file-hunter index is browsed comfortably), `U` for the parent
directory, `R` to go back to the repositories.

The modem downloads the file (HTTPS, redirects and zip extraction included: file-hunter
serves one zip per game, archive.org extracts the TOSEC zips on the server side) and NETROM
then offers to:

 * **Save** it to disk (a DOS file name is proposed from the ROM name, 1024 byte blocks over
   the UART, about 10 KB/s)
 * **Run** it: plain cartridge images of 8, 16 or 32 KB with the `AB` header at the start
   are copied to RAM at 4000h/8000h and the machine is reset, so the BIOS finds and starts
   the "cartridge" exactly as if it were plugged in. This is the classic ROM-in-RAM trick:
   it works with most simple cartridges, but not with MegaROMs (Konami, ASCII 8/16 mappers),
   48/64 KB ROMs that need page 0, or games that check that they run from real ROM. For
   those, save the file and use SofaRun or another loader with a MegaFlashROM, Carnivore2
   or similar device.

MSX-DOS 1 converts the command line to upper case, so type URLs in the menu (`U`) or put
them in `NETROM.CFG` on DOS 1.

Note for file-hunter: the site refuses download managers and clients without a browser
like User-Agent; the modem identifies itself as `Mozilla/5.0 (compatible; NiFi-MSX/...)`
(see `HTTP_USER_AGENT` in `configuration.h`). Please respect their usage rules.

## ZXUno proof-of-concept code

There is also example of usage firmware with ZXUno's uart - it downloads screen dump(to screen) from gopher server

## Testing from a PC

`tester/tester.py` exercises the WiFi, DNS and active TCP commands. `tester/tester_passive.py`
opens a listening connection on port 2323 and echoes everything it receives (connect to it with
`nc <modem ip> 2323`). `tester/tester_rom.py COMx list <url>` and `tester_rom.py COMx get <url> <file>`
drive the ROM loader commands from a PC and verify the CRC of the transfer.

`tester/inflate_test.cpp` checks the DEFLATE decoder on a PC against any zip file:

```
g++ -O2 -o inflate_test tester/inflate_test.cpp Nifi/inflate.cpp
./inflate_test some.zip
```

## Limitations

 * UDP implementations isn't stable but good enough for getting time from SNTP

 * SSL/TLS is unimplemented (TCPIP_TCP_OPEN returns ERR_NOT_IMP when the TLS flags are set)

 * TCP urgent data, PUSH flag control and TCPIP_TCP_DISCARD are not supported (data is sent
   synchronously, there is no output buffer)

 * The active open blocks until the connection is established or the timeout expires
   (features flag "TCP_OPEN is blocking" is advertised)

 * When the remote host closes a connection that has no pending data, the ESP8266 core
   releases it at once, so the connection goes straight to the "closed" state instead of
   passing through CLOSE-WAIT

 * ROM loader: HTTPS certificates are not verified (the ESP has no clock nor trust store;
   the zip CRC-32 protects the integrity of the file). Zips with several files give the
   first ROM-looking entry. Downloads are limited by the free flash of the module
   (`MAX_ROM_DOWNLOAD`, 2 MB by default). Running from RAM only covers plain 8/16/32 KB
   cartridges, see NETROM above

## License

The whole project (firmware, driver, tools, documentation) is licensed under the
GNU General Public License version 3 or later: see [LICENSE](LICENSE). Every source file
carries the notice. The original NiFi code by Alexander Sharihin was published under
GPLv3 / LGPLv3 terms, which allow this.

Copyright (C) 2026 Andrés Ortiz.
Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander Sharihin), Copyright (C) 2021,
and on work by Ducasp (Oduvaldo Pavan Junior), Copyright (C) 2020. See [Credits](#credits).

## Do you want support project?

Feel free contribute any code to project, write me "thanks" to email or send some money to my PayPal wallet(also it's my email for contacts): anihirash@gmail.com

## Do you want feature X?

Please, make issue - it will allows track all requests.

If this feature linked with support of some hardware - I'll need it. I have some devices and can cover some list by myself(for example ZXUno, original ZX Spectrum +2A, Spectrum Next, MSX2).

If this feature can be covered via existed hardware - there no need to ship me device.

## Can I make device for you?

Short answer - No. I don't like produce hardware.

I did some only by one reason - I haven't another choice.

## Can you use it in your commercial hardware?

Of cause! With respect to GPLv3.

## Should you pay royalties for it?

As you wish. I'm not against it.

## Credits

This version (NiFi UNAPI V2) is maintained by **Andrés Ortiz** and builds on the work of:

 * **Andrés Ortiz (2026)** - this version: passive TCP and the whole UNAPI TCP/IP 1.1 TCP
   function set in the firmware and the driver, NIFICFG (friendly WiFi configuration, UART
   detection, firmware updates over the air and from disk), NETROM and the firmware ROM
   loader (HTTP(S) downloads, zip extraction, directory listings), support for the 16C550
   without AFE, test tools and documentation.
 * **Nihirash (Alexander Sharihin, 2021)** - original NiFi: the ESP8266 binary protocol
   firmware, the MSX UNAPI driver and tools and the ZX-Uno example code.
   <https://github.com/nihirash/esp-binary-firmware>
 * **Ducasp (Oduvaldo Pavan Junior, 2020)** - the UNAPI driver for custom ESP firmware that
   Nihirash used as the skeleton of the NiFi driver, and the 16C550CZiModem UART library
   (chip detection, interrupt driven reception and software flow control for the 16C550
   without AFE), whose approach the non-AFE support of this version follows. The code of
   this repository was written for the NiFi protocol and does not copy his library, which
   is distributed under different terms.
   <https://github.com/ducasp/MSX-Development>

Thanks also to Konamiman for the UNAPI specification this driver implements.
