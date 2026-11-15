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

"""Passive (listening) TCP test for the NiFi firmware 0.2+

Connect the ESP8266 to a PC serial port, run this script and then connect
to the modem from another machine (or the same one) with e.g.

    nc <modem ip> 2323

Everything typed in netcat is echoed back by the modem through this script.
Requires pyserial.
"""
import serial
import sys
import time

port = sys.argv[1] if len(sys.argv) > 1 else "COM3"
LISTEN_PORT = 2323

uart = serial.Serial(port=port, baudrate=115200, rtscts=False)

OP_RESET         = b'\x00'
OP_GET_FEATURES  = b'\x01'
OP_GET_IP        = b'\x02'
OP_CLOSE_TCP     = b'\x0E'
OP_SEND_TCP      = b'\x11'
OP_RECV_TCP      = b'\x12'
OP_EXT_STATUS    = b'\x13'
OP_OPEN_TCP_EX   = b'\x14'
OP_ABORT_TCP     = b'\x15'
OP_GET_AP        = b'\x32'

ERR_OK      = 0
ERR_NO_CONN = 11

STATE_NAMES = ["closed", "LISTEN", "SYN-SENT", "SYN-RECEIVED", "ESTABLISHED",
               "FIN-WAIT-1", "FIN-WAIT-2", "CLOSE-WAIT", "CLOSING", "LAST-ACK", "TIME-WAIT"]
CLOSE_REASONS = ["unknown", "never used", "closed locally", "aborted locally", "RST received",
                 "user timeout", "establishment timeout", "network lost", "unreachable"]


def get_byte():
    return uart.read(1)[0]


def get_word():
    return int.from_bytes(uart.read(2), "little")


def put_word(w):
    uart.write(w.to_bytes(2, "little"))


def reset():
    print("Resetting modem...", end="", flush=True)
    while True:
        uart.write(OP_RESET)
        if get_byte() == ERR_OK and uart.read(5) == b'NiFi\x00':
            print(" ok")
            return


def capabilities():
    uart.write(OP_GET_FEATURES + b'\x01')
    assert get_byte() == ERR_OK
    caps = get_word()
    print("Capabilities: %04X (active TCP: %s, passive TCP: %s)" % (
        caps, bool(caps & 8), bool(caps & 32)))


def local_ip():
    uart.write(OP_GET_IP + b'\x01')
    if get_byte() != ERR_OK:
        return None
    return ".".join(str(b) for b in uart.read(4))


def open_passive(local_port, remote_ip=(0, 0, 0, 0), remote_port=0xFFFF):
    uart.write(OP_OPEN_TCP_EX + bytes(remote_ip))
    put_word(remote_port)
    put_word(local_port)
    put_word(0)          # default timeout
    uart.write(b'\x01')  # flags: passive
    err = get_byte()
    if err == ERR_OK:
        return get_byte()
    if err == ERR_NO_CONN:
        print("Open failed, close reason:", CLOSE_REASONS[get_byte()])
    else:
        print("Open failed, error", err)
    return None


def status(conn):
    uart.write(OP_EXT_STATUS + bytes([conn]))
    err = get_byte()
    if err == ERR_NO_CONN:
        reason = get_byte()
        return None, reason, 0
    assert err == ERR_OK
    ip = ".".join(str(b) for b in uart.read(4))
    rport = get_word()
    lport = get_word()
    state = get_byte()
    get_byte()  # flags
    avail = get_word()
    return (state, ip, rport, lport), None, avail


def recv(conn, size):
    uart.write(OP_RECV_TCP + bytes([conn]))
    put_word(size)
    if get_byte() != ERR_OK:
        return b''
    return uart.read(get_word())


def send(conn, data):
    uart.write(OP_SEND_TCP + bytes([conn]))
    put_word(len(data))
    if get_byte() == ERR_OK:
        uart.write(data)


def close(conn):
    uart.write(OP_CLOSE_TCP + bytes([conn]))
    return get_byte()


reset()
capabilities()
ip = local_ip()
if ip is None:
    print("The modem is not connected to a WiFi network. Configure it first.")
    sys.exit(1)

conn = open_passive(LISTEN_PORT)
if conn is None:
    sys.exit(1)
print("Connection %d listening on %s:%d - connect with: nc %s %d" % (conn, ip, LISTEN_PORT, ip, LISTEN_PORT))

last_state = None
while True:
    info, reason, avail = status(conn)
    if info is None:
        print("Connection closed:", CLOSE_REASONS[reason] if reason < len(CLOSE_REASONS) else reason)
        break
    state = info[0]
    if state != last_state:
        print("State: %s  peer %s:%d  local port %d" % (STATE_NAMES[state], info[1], info[2], info[3]))
        last_state = state
    if avail:
        data = recv(conn, avail)
        print("Received %d bytes: %r" % (len(data), data))
        send(conn, b"echo: " + data)
        if data.strip() == b"quit":
            print("Closing, result", close(conn))
            break
    time.sleep(0.05)
