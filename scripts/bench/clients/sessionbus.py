# A client of the session bus without libraries, enough to send a notification and close it again: D-Bus messages
# marshalled by hand (little endian), EXTERNAL authentication as the user running it.
import os
import socket
import struct
import time

METHOD_CALL, METHOD_RETURN, ERROR = 1, 2, 3
REPLY_SERIAL = 5


def pad(buf, n):
    return buf + b"\0" * (-len(buf) % n)


def mstring(s):  # s and o: aligned to 4 before
    b = s.encode()
    return struct.pack("<I", len(b)) + b + b"\0"


def msig(s):  # g
    b = s.encode()
    return bytes([len(b)]) + b + b"\0"


class SessionBus:
    def __init__(self):
        address = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
        if "unix:path=" in address:
            path = address.split("unix:path=", 1)[1].split(",")[0]
        else:
            path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "bus")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(path)
        self.sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
        if not self.line().startswith(b"OK"):
            raise SystemExit("latency: the session bus refused the connection")
        self.sock.sendall(b"BEGIN\r\n")
        self.serial = 0
        self.data = b""
        self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello")

    def line(self):
        buf = b""
        while not buf.endswith(b"\r\n"):
            chunk = self.sock.recv(1)
            if not chunk:
                raise SystemExit("latency: the session bus closed the connection")
            buf += chunk
        return buf

    def message(self, destination, path, interface, member, signature, body):
        """A method call, and its serial"""
        self.serial += 1
        fields = b""
        values = [(1, "o", path), (2, "s", interface), (3, "s", member), (6, "s", destination)]
        if signature:
            values.append((8, "g", signature))
        for code, sig, value in values:
            fields = pad(fields, 8) + bytes([code]) + msig(sig)
            fields += msig(value) if sig == "g" else pad(fields, 4)[len(fields):] + mstring(value)
        head = struct.pack("<cBBBIII", b"l", METHOD_CALL, 0, 1, len(body), self.serial, len(fields)) + fields
        return pad(head, 8) + body, self.serial

    def read(self):
        """The next message: its type, header fields and body"""
        while len(self.data) < 16:
            self.more()
        _, mtype, _, _, blen, _, flen = struct.unpack_from("<cBBBIII", self.data)
        total = 16 + (flen + 7) // 8 * 8 + blen
        while len(self.data) < total:
            self.more()
        msg, self.data = self.data[:total], self.data[total:]
        return mtype, msg[16 : 16 + flen], msg[total - blen :]

    def more(self):
        chunk = self.sock.recv(1 << 16)
        if not chunk:
            raise SystemExit("latency: the session bus closed the connection")
        self.data += chunk

    @staticmethod
    def header(fields):
        """The header fields by code, for the ones that are strings, signatures or integers"""
        found, off = {}, 0
        while off < len(fields):
            code, n = fields[off], fields[off + 1]
            sig = fields[off + 2 : off + 2 + n]
            off += 3 + n
            if sig in (b"s", b"o"):
                off += -off % 4
                (n,) = struct.unpack_from("<I", fields, off)
                found[code] = fields[off + 4 : off + 4 + n].decode()
                off += 5 + n
            elif sig == b"g":
                n = fields[off]
                found[code] = fields[off + 1 : off + 1 + n].decode()
                off += 2 + n
            elif sig == b"u":
                off += -off % 4
                (found[code],) = struct.unpack_from("<I", fields, off)
                off += 4
            else:
                raise SystemExit(f"latency: a header field of type {sig} in a message from the bus")
            off += -off % 8
        return found

    def send(self, destination, path, interface, member, signature="", body=b""):
        """Sends a method call and returns its serial and the moment it went out (CLOCK_MONOTONIC, ns)"""
        msg, serial = self.message(destination, path, interface, member, signature, body)
        stamp = time.clock_gettime_ns(time.CLOCK_MONOTONIC)
        self.sock.sendall(msg)
        return serial, stamp

    def reply(self, serial):
        """The body of the reply to a call, once it arrives"""
        while True:
            mtype, fields, body = self.read()
            if mtype not in (METHOD_RETURN, ERROR) or self.header(fields).get(REPLY_SERIAL) != serial:
                continue
            if mtype == ERROR:
                raise SystemExit(f"latency: the bus answered an error: {self.header(fields).get(4, '')}")
            return body

    def call(self, destination, path, interface, member, signature="", body=b""):
        return self.reply(self.send(destination, path, interface, member, signature, body)[0])

    def notify(self, app, summary, text):
        """Sends a notification like notify-send and returns the serial of the call (its reply holds the id) and the
        moment it went out"""
        body = mstring(app)
        body = pad(body, 4) + struct.pack("<I", 0)  # replaces nothing
        body = pad(body, 4) + mstring("")  # no icon
        body = pad(body, 4) + mstring(summary)
        body = pad(body, 4) + mstring(text)
        body = pad(body, 4) + struct.pack("<I", 0)  # no actions
        body = pad(pad(body, 4) + struct.pack("<I", 0), 8)  # no hints, the elements would be aligned to 8
        body = pad(body, 4) + struct.pack("<i", -1)  # the server's default duration
        return self.send("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                         "Notify", "susssasa{sv}i", body)

    def notification_id(self, serial):
        return struct.unpack_from("<I", self.reply(serial))[0]

    def close_notification(self, nid):
        self.call("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
                  "CloseNotification", "u", struct.pack("<I", nid))

    def close(self):
        self.sock.close()
