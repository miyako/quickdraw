"""Small original PICT v1 fixtures; no historical artwork or fonts."""
from pathlib import Path
import struct


def picture(operations):
    return b"\0\0" + struct.pack(">hhhh", 0, 0, 8, 8) + b"\x11\x01" + operations + b"\xff"


def resource_fork(payload):
    data = struct.pack(">I", len(payload)) + payload
    header = struct.pack(">IIII", 256, 256 + len(data), len(data), 50)
    resource_map = header + b"\0" * 8 + struct.pack(">HH", 28, 50)
    resource_map += struct.pack(">H4sHHhH", 0, b"PICT", 0, 10, 128, 65535) + b"\0" * 8
    return header + b"\0" * 240 + data + resource_map


def write_fixtures(destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    rect = struct.pack(">hhhh", 1, 1, 7, 7)
    fixtures = {
        "rectangle.pict": picture(b"\x31" + rect),
        "oval.pict": picture(b"\x51" + rect),
        "text.pict": picture(b"\x28" + struct.pack(">hh", 5, 1) + b"\x01A"),
        "malformed.pict": b"\0",
        "font-map.json": b'{"schema":1,"fonts":[]}\n',
        "fonts.rsrc": resource_fork(picture(b"\x31" + rect)),
    }
    for name, content in fixtures.items():
        (destination / name).write_bytes(content)


if __name__ == "__main__":
    write_fixtures(Path(__file__).parent / "host/Resources")
