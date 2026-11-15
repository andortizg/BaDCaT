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

import serial
port = "/dev/cu.usbserial-1410" # your uart. In windows use just COM3, COM12 etc

SSID     = "PinnCom"     # put here your wifi creds
PASSWORD = "lobotomy"

uart = serial.Serial(port=port, baudrate=57600)

OP_Reset        = b'\x00'
OP_GET_FEATURES = b'\x01'
OP_GET_IP       = b'\x02'
OP_GET_NETSTATE = b'\x03'
OP_RESOLVE_DNS  = b'\x06'
OP_OPEN_UDP     = b'\x08'
OP_CLOSE_UDP    = b'\x09'
OP_STATUS_UDP   = b'\x0A'
OP_SEND_DATAGR  = b'\x0B'
OP_RECV_DATAGR  = b'\x0C'
OP_OPEN_TCP     = b'\x0D'
OP_CLOSE_TCP    = b'\x0E'
OP_STATUS_TCP   = b'\x10'
OP_SEND_TCP     = b'\x11'
OP_RECV_TCP     = b'\x12'
OP_CONF_AUTO_IP = b'\x19'
OP_CONF_IP      = b'\x1A'
OP_GET_AP_LIST  = b'\x30'
OP_SET_AP       = b'\x31'
OP_GET_AP       = b'\x32'
OP_VERSION_STR  = b'\xff'

IP_LOCAL = b'\x01'
IP_REMOTE = b'\x02'
IP_MASK = b'\x03'
IP_GATEWAY = b'\x04'
IP_DNS1 = b'\x05'
IP_DNS2 = b'\x06'

CONN_STATE_UNK = b'\x00'
CONN_STATE_EST = b'\x04'

def publish_byte(b):
    uart.write(b)

def publish_word(w):
    publish_byte(int(w & 255).to_bytes(1, "little"))
    publish_byte(int(w / 255).to_bytes(1, "little"))

def get_byte():
    b = uart.read(1)
    return b

def get_word():
    w = uart.read(2)
    return int.from_bytes(w, "little")

def get_str():
    string = b''
    while 1:
        c = get_byte()
        if c == b'\x00': 
            break
        string = string + c
    return string.decode("ascii")

def get_block(s):
    return uart.read(s).decode("ascii")

def publish_str(s):
    b = bytes(s, "ascii")
    publish_byte(b)
    publish_byte(b'\x00')

def get_ip_addr():
    ip = str(int.from_bytes(get_byte(), "little")) + "." +str(int.from_bytes(get_byte(), "little")) + "." + str(int.from_bytes(get_byte(), "little")) + "." + str(int.from_bytes(get_byte(), "little"))
    return ip

error_codes = [
    'success',                    # 0
    'not implemented',            # 1
    'no network',                 # 2
    'no data',                    # 3
    'invalid parameters',         # 4
    'query exists',               # 5
    'invalid ip',                 # 6
    'no dns',                     # 7
    'dns resolve error',          # 8
    'no free connections',        # 9
    'conection exists',           # 10
    'no connection',              # 11
    'wrong connection state',     # 12
    'buffer issue',               # 13
    'too large datagram',         # 14
    'invalid operation',          # 15
    'auth failed',                # 16
]

def check_error():
    b = get_byte()
    ec = int.from_bytes(b, "little")
    print (str(ec) + " ", end='')
    print(error_codes[ec])
    return b

def reset():
    print("Resetting...", end='')
    while 1:
        uart.write(OP_Reset)
        
        if check_error() == b'\x00':
            if get_byte() == b'N' and get_byte() == b'i' and get_byte() == b'F' and get_byte() == b'i' and get_byte() == b'\x00':
                print("Got init!")
                return 

def getver():
    uart.write(OP_VERSION_STR)
    print("Getting version...", end='')
    if check_error() == b'\x00':
        print(get_str())

def get_current_ap():
    uart.write(OP_GET_AP)
    print("Getting current AP....", end='')
    if check_error() == b'\x00':
        print(get_str())

def get_ap_list():
    uart.write(OP_GET_AP_LIST)
    print("Getting AP list....", end='')
    if check_error() == b'\x00':
        while 1:
            f = get_byte()
            if f == b'\xff':
                return
            s = f.decode("ascii") + get_str()
            print(s)

def set_ap(ssid, password):
    print("Setting AP=" + ssid + " and Pass=" + password + "...", end='')
    uart.write(OP_SET_AP)
    publish_str(ssid)
    publish_str(password)
    check_error()
    
def get_ip(ip):
    print("Getting info about IP address: ....", end='')
    uart.write(OP_GET_IP)
    uart.write(ip)
    if check_error() == b'\x00':
        ip = get_ip_addr()
        print(ip)

def get_netstate():
    print("Getting info about network state....", end='')
    uart.write(OP_GET_NETSTATE)
    if check_error() == b'\x00':
        state = get_byte()
        if state == b'\x00':
            print("Closed")
        if state == b'\x01':
            print("Opening")
        if state == b'\x02':
            print("Open")
        if state == b'\x03':
            print("Closing")
        if state == b'\xff':
            print("Unknown")

def resolve(domain):
    print("Resolving dns name("+domain+")....", end='')
    uart.write(OP_RESOLVE_DNS)
    publish_str(domain)
    if check_error() == b'\x00':
        ip = get_ip_addr()
        print(ip)
        return ip

def opentcp(addr, port):
    def atoc(i):
        return int(i).to_bytes(1, "little")
    parts = list(map(atoc, addr.split('.')))
    print("Opening connection to " + addr + ":" + str(port) +"...", end='')
    publish_byte(OP_OPEN_TCP)
    for p in parts:
        publish_byte(p)

    publish_word(port)


    if check_error() == b'\x00':
        c = get_byte()
        print ("Connection number: "+ str(int.from_bytes(c, "little")))
        return int.from_bytes(c, "little")

def closetcp(number):
    print("Closing connection number " + str(number) + "...", end='')
    c = number.to_bytes(1, "little")
    publish_byte(OP_CLOSE_TCP)
    publish_byte(c)
    check_error()

def sendtcp(conn, s):
    b = s.encode("ascii")
    l = len(b)
    print("Sending " + str(l) + " bytes to connection " + str(conn) +"...")
    conn = conn.to_bytes(1, "little")
    publish_byte(OP_SEND_TCP)
    publish_byte(conn)
    publish_word(l)
    if check_error() == b'\x00':
        for c in b:
            publish_byte(c.to_bytes(1, "little"))

def tcpstatus(conn):
    print("Receivign status from TCP-connection " + str(conn) + "...", end='')
    publish_byte(OP_STATUS_TCP)
    publish_byte(conn.to_bytes(1, "little"))
    if check_error() == b'\x00':
        state = get_byte()
        avail = get_word()
        if state == CONN_STATE_EST:
            print("Connection established")
        else:
            print("Connection closed")

        print("Avail " + str(avail) + " bytes")
        return (state, avail)

def recvtcp(conn, bs):
    print("Receiving " + str(bs) + " bytes from TCP-connection " + str(conn) + "...", end='')
    publish_byte(OP_RECV_TCP)
    publish_byte(conn.to_bytes(1, "little"))
    publish_word(bs)
    if check_error() == b'\x00':
        l = get_word()
        print(str(l) + " bytes received")
        b = get_block(l)
        print("Received block:")
        print(b)
        return b

reset()
getver()
get_current_ap()
get_ap_list()
set_ap(SSID, PASSWORD)
print("Local ip:")
get_ip(IP_LOCAL)
print("Remote ip:")
get_ip(IP_REMOTE)
print("Gateway ip:")
get_ip(IP_GATEWAY)
print("Netmask:")
get_ip(IP_MASK)
print("DNS 1:")
get_ip(IP_DNS1)
print("DNS 2:")
get_ip(IP_DNS2)
get_netstate()
ip = resolve("nihirash.net")
ip2 = resolve("google.com")
if ip != None:
    c1 = opentcp(ip, 70)
    c2 = None
    if ip2 != None:
        c2 = opentcp(ip2, 80)
        if c2 != None:
            sendtcp(c2, "GET / HTTP/1.0\r\n\r\n")
    if (c1 != None):
        sendtcp(c1, "/guest.cgi\r\n")
        avail = 0
        state= CONN_STATE_EST
        while (state == CONN_STATE_EST):
            state, avail = tcpstatus(c1)
            if (avail > 0):
                recvtcp(c1, avail)

        closetcp(c1) # Should fail - connection already closed
    if (c2 != None):
        avail = 0
        state= CONN_STATE_EST
        while (state == CONN_STATE_EST):
            state, avail = tcpstatus(c2)
            if (avail > 0):
                recvtcp(c2, avail)
    else:
        print("Connection wasn't established")
else:
    print("DNS wasn't resolved - can't make request")