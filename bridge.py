"""
Sisi PC: nyambung ke app Virtual Steer di iPhone lewat kabel USB (usbmuxd),
terus bikin controller Xbox 360 virtual.

Butuh (Windows): iTunes atau Apple Devices (ada Apple Mobile Device Service),
                 pip install vgamepad
Jalanin: python bridge.py   (app Virtual Steer harus kebuka di iPhone)
"""
import argparse
import os
import plistlib
import socket
import struct
import sys
import time

MUX_PORT = 27015  # usbmuxd di Windows = TCP localhost; di macOS/Linux = /var/run/usbmuxd


def mux_connect():
    if sys.platform != "win32" and os.path.exists("/var/run/usbmuxd"):
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(2)
        s.connect("/var/run/usbmuxd")
        return s
    return socket.create_connection(("127.0.0.1", MUX_PORT), timeout=2)


def recvn(s, n):
    buf = b""
    while len(buf) < n:
        chunk = s.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("usbmuxd nutup")
        buf += chunk
    return buf


def mux_call(s, msg):
    msg = {"ClientVersionString": "virtual-steer", "ProgName": "virtual-steer", **msg}
    data = plistlib.dumps(msg)
    s.sendall(struct.pack("<IIII", 16 + len(data), 1, 8, 1) + data)
    length = struct.unpack("<IIII", recvn(s, 16))[0]
    return plistlib.loads(recvn(s, length - 16))


def open_tunnel(port):
    s = mux_connect()
    try:
        devices = mux_call(s, {"MessageType": "ListDevices"}).get("DeviceList", [])
    finally:
        s.close()
    usb = [d for d in devices if d.get("Properties", {}).get("ConnectionType") == "USB"]
    if not usb:
        raise LookupError("iPhone belum kedeteksi lewat USB (colok kabel, tap Trust)")
    s = mux_connect()
    reply = mux_call(s, {
        "MessageType": "Connect",
        "DeviceID": usb[0]["DeviceID"],
        "PortNumber": socket.htons(port),
    })
    if reply.get("Number") != 0:
        s.close()
        raise ConnectionRefusedError("app Virtual Steer belum kebuka di iPhone")
    return s


def main():
    global MUX_PORT
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5555)
    ap.add_argument("--mux-port", type=int, default=MUX_PORT)
    args = ap.parse_args()
    MUX_PORT = args.mux_port

    import vgamepad as vg

    pad = vg.VX360Gamepad()
    btn = {"u": vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER,   # gear up = RB
           "d": vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER}    # gear down = LB
    held = {"u": False, "d": False}

    def set_button(k, down):
        if down and not held[k]:
            pad.press_button(button=btn[k])
        elif not down and held[k]:
            pad.release_button(button=btn[k])
        held[k] = down

    def apply(steer, gas, brake, up, down):
        pad.left_joystick_float(x_value_float=max(-1.0, min(1.0, steer)), y_value_float=0.0)
        pad.right_trigger_float(value_float=max(0.0, min(1.0, gas)))
        pad.left_trigger_float(value_float=max(0.0, min(1.0, brake)))
        set_button("u", up)
        set_button("d", down)
        pad.update()

    def neutral():
        apply(0.0, 0.0, 0.0, False, False)

    last_msg = None
    while True:
        try:
            sock = open_tunnel(args.port)
        except (OSError, LookupError) as e:
            if str(e) != last_msg:
                print(f"{e} - nunggu...")
                last_msg = str(e)
            time.sleep(1)
            continue
        last_msg = None
        print("Nyambung ke iPhone (lewat kabel)")
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        sock.settimeout(1.0)
        buf = b""
        try:
            while True:
                try:
                    chunk = sock.recv(4096)
                except socket.timeout:
                    neutral()          # HP diem >1 dtk = lepas semua input
                    continue
                if not chunk:
                    break
                buf += chunk
                if b"\n" not in buf:
                    continue
                *lines, buf = buf.split(b"\n")
                try:    # cuma pake state terbaru biar ga numpuk (minim delay)
                    s, g, b, u, d = lines[-1].split()
                    apply(float(s), float(g), float(b), u == b"1", d == b"1")
                except ValueError:
                    pass
        except OSError:
            pass
        finally:
            sock.close()
            neutral()
            print("Putus, nyambung ulang...")


if __name__ == "__main__":
    main()
