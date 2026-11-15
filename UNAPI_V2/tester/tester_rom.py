# NiFi UNAPI V2 - ESP8266 firmware, UNAPI driver and MSX-DOS tools
# for the BadCat WiFi cartridge.
#
# Copyright (C) 2026 Andrés Ortiz
# Based on the NiFi firmware and UNAPI drivers by Nihirash (Alexander
# Sharihin), Copyright (C) 2021, https://github.com/nihirash/esp-binary-firmware
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later

"""ROM loader test for the NiFi firmware 0.3+ (commands 0x40-0x47)

Drives the modem from a PC serial port exactly like NETROM.COM does:

    python tester_rom.py COM3 list https://download.file-hunter.com/Games/MSX1/ROM/ [filter]
    python tester_rom.py COM3 get  https://download.file-hunter.com/Games/MSX1/ROM/Akarui%20Nouen%20%281983%29%28Hudson%20Soft%29.zip out.rom

"list" prints the first entries of a directory listing (optionally filtered),
"get" downloads an URL (zip files are unpacked by the modem), transfers the
result over the UART, checks the CRC-32 reported by the modem and saves it.
Requires pyserial.
"""
import serial
import sys
import time
import zlib

if len(sys.argv) < 4:
    print(__doc__)
    sys.exit(2)

port, command, url = sys.argv[1], sys.argv[2], sys.argv[3]
uart = serial.Serial(port=port, baudrate=115200, rtscts=False, timeout=None)

OP_RESET      = 0x00
OP_LIST_URL   = 0x40
OP_LIST_GET   = 0x41
OP_LIST_ENTER = 0x42
OP_LIST_UP    = 0x43
OP_GET_ENTRY  = 0x44
OP_GET_URL    = 0x45
OP_FILE_READ  = 0x46
OP_LOCATION   = 0x47

ERR_HTTP = 17
ERRORS = {0: "ok", 2: "no network", 3: "no file downloaded", 4: "invalid parameter",
          13: "out of memory", 14: "too large", 15: "invalid operation", 17: "HTTP error",
          18: "bad archive", 19: "flash storage error"}


def get_byte():
    return uart.read(1)[0]


def get_word():
    return int.from_bytes(uart.read(2), "little")


def get_dword():
    return int.from_bytes(uart.read(4), "little")


def get_string():
    out = bytearray()
    while True:
        c = get_byte()
        if c == 0:
            return out.decode("ascii", "replace")
        out.append(c)


def put_string(s):
    uart.write(s.encode("ascii") + b"\0")


def result():
    """Reads the error byte (and the HTTP status for error 17). Returns the error code."""
    err = get_byte()
    if err == ERR_HTTP:
        status = get_word()
        detail = {0: "could not connect", 1: "transfer failed", 2: "redirect loop"}.get(status, "HTTP %d" % status)
        print("Error: %s" % detail)
    elif err:
        print("Error %d: %s" % (err, ERRORS.get(err, "?")))
    return err


def reset():
    print("Resetting modem...", end="", flush=True)
    uart.timeout = 1
    while True:
        uart.write(bytes([OP_RESET]))
        head = uart.read(6)
        if head == b"\0NiFi\0":
            break
    uart.timeout = None
    print(" ok")


def list_dir(url, filt=""):
    uart.write(bytes([OP_LIST_URL]))
    put_string(url)
    t = time.time()
    if result():
        return
    count = get_word()
    print("%d entries (%.1f s)" % (count, time.time() - t))

    uart.write(bytes([OP_LOCATION]))
    get_byte()
    print("Location:", get_string())

    start = 0
    while True:
        uart.write(bytes([OP_LIST_GET]) + start.to_bytes(2, "little") + bytes([20]))
        put_string(filt)
        if result():
            return
        total = get_word()
        n = get_byte()
        for _ in range(n):
            index = get_word()
            flags = get_byte()
            size = get_dword()
            name = get_string()
            kind = "<DIR>" if flags & 1 else "%7d" % size
            print("%5d  %s  %s" % (index, kind, name))
        start += n
        if n == 0 or start >= total:
            print("%d matching entries" % total)
            return
        if input("-- more (Enter) / q: ").strip().lower() == "q":
            return


def download(url, out_path):
    uart.write(bytes([OP_GET_URL]))
    put_string(url)
    print("Downloading on the modem...", end="", flush=True)
    t = time.time()
    if result():
        return
    size = get_dword()
    crc = get_dword()
    name = get_string()
    print(" done in %.1f s: %s, %d bytes, CRC %08X" % (time.time() - t, name, size, crc))

    data = bytearray()
    t = time.time()
    while len(data) < size:
        uart.write(bytes([OP_FILE_READ]) + len(data).to_bytes(4, "little") + (1024).to_bytes(2, "little"))
        if result():
            return
        n = get_word()
        if n == 0:
            break
        data += uart.read(n)
        print("\r%d / %d bytes" % (len(data), size), end="", flush=True)
    elapsed = time.time() - t
    print("\nTransferred in %.1f s (%.1f KB/s)" % (elapsed, len(data) / 1024 / max(elapsed, 0.001)))

    actual = zlib.crc32(bytes(data)) & 0xFFFFFFFF
    print("CRC check:", "OK" if actual == crc and len(data) == size else "FAILED (%08X)" % actual)
    with open(out_path, "wb") as f:
        f.write(data)
    print("Saved to", out_path)
    if data[:2] == b"AB":
        init = int.from_bytes(data[2:4], "little")
        print("Cartridge header found, INIT at %04Xh" % init)


reset()
if command == "list":
    list_dir(url, sys.argv[4] if len(sys.argv) > 4 else "")
elif command == "get":
    download(url, sys.argv[4] if len(sys.argv) > 4 else "download.rom")
else:
    print("unknown command", command)
