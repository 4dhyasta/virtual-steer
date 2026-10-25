"""
PC side: connects to the Virtual Steer app on the iPhone over the USB cable (usbmuxd)
and exposes a virtual Xbox 360 controller.

Needs (Windows): iTunes or Apple Devices (installs Apple Mobile Device Service)
                 pip install vgamepad
Run:             python bridge.py   (the Virtual Steer app must be open on the iPhone)

Mapping: steering = left stick X, throttle = RT, brake = LT,
         gear up = RB, gear down = LB, handbrake = X
"""
import argparse
import os
import plistlib
import socket
import struct
import sys
import time

MUX_PORT = 27015  # usbmuxd on Windows = TCP localhost; on macOS/Linux = /var/run/usbmuxd


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
            raise ConnectionError("usbmuxd closed the connection")
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
        raise LookupError("iPhone not detected over USB (plug in the cable and tap Trust)")
    s = mux_connect()
    reply = mux_call(s, {
        "MessageType": "Connect",
        "DeviceID": usb[0]["DeviceID"],
        "PortNumber": socket.htons(port),
    })
    if reply.get("Number") != 0:
        s.close()
        raise ConnectionRefusedError("Virtual Steer app is not open on the iPhone")
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
    btn = {"u": vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER,   # gear up   = RB
           "d": vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER,    # gear down = LB
           "h": vg.XUSB_BUTTON.XUSB_GAMEPAD_X}                # handbrake = X
    held = {"u": False, "d": False, "h": False}

    def set_button(k, down):
        if down and not held[k]:
            pad.press_button(button=btn[k])
        elif not down and held[k]:
            pad.release_button(button=btn[k])
        held[k] = down

    def apply(steer, gas, brake, up, down, hand):
        pad.left_joystick_float(x_value_float=max(-1.0, min(1.0, steer)), y_value_float=0.0)
        pad.right_trigger_float(value_float=max(0.0, min(1.0, gas)))
        pad.left_trigger_float(value_float=max(0.0, min(1.0, brake)))
        set_button("u", up)
        set_button("d", down)
        set_button("h", hand)
        pad.update()

    def neutral():
        apply(0.0, 0.0, 0.0, False, False, False)

    last_msg = None
    while True:
        try:
            sock = open_tunnel(args.port)
        except (OSError, LookupError) as e:
            if str(e) != last_msg:
                print(f"{e} - waiting...")
                last_msg = str(e)
            time.sleep(1)
            continue
        last_msg = None
        print("Connected to iPhone over USB")
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
                    neutral()          # phone silent for >1 s = release every input
                    continue
                if not chunk:
                    break
                buf += chunk
                if b"\n" not in buf:
                    continue
                *lines, buf = buf.split(b"\n")
                try:    # only use the newest state so nothing piles up (minimum delay)
                    p = lines[-1].split()
                    apply(float(p[0]), float(p[1]), float(p[2]),
                          p[3] == b"1", p[4] == b"1", len(p) > 5 and p[5] == b"1")
                except (ValueError, IndexError):
                    pass
        except OSError:
            pass
        finally:
            sock.close()
            neutral()
            print("Disconnected, reconnecting...")


if __name__ == "__main__":
    main()
