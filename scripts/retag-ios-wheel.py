#!/usr/bin/env python3
"""Retag a cibuildwheel iOS wheel to the deployment target used by this app.

cibuildwheel 4.2 can emit an ios_13_0 filename for CPython 3.13 device wheels
while the extension itself is compiled with IPHONEOS_DEPLOYMENT_TARGET=26.0.
Blender unpacks these wheels into its private Python tree rather than publishing
them, but the build harness deliberately requires truthful wheel metadata.

This repair hook rewrites only the platform tag and RECORD. The workflow still
validates every extracted Mach-O with vtool before it can enter the app bundle.
"""

from __future__ import annotations

import base64
import csv
import hashlib
import io
import re
import sys
import zipfile
from pathlib import Path

TARGET_TAG = "ios_26_0_arm64_iphoneos"
IOS_TAG_RE = re.compile(r"ios_\d+_\d+_arm64_iphoneos")


def digest(data: bytes) -> str:
    value = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b"=")
    return "sha256=" + value.decode("ascii")


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: retag-ios-wheel.py WHEEL DEST_DIR")

    source = Path(sys.argv[1]).resolve()
    dest_dir = Path(sys.argv[2]).resolve()
    dest_dir.mkdir(parents=True, exist_ok=True)

    if TARGET_TAG in source.name:
        destination = dest_dir / source.name
        destination.write_bytes(source.read_bytes())
        print(destination)
        return 0

    new_name, replacements = IOS_TAG_RE.subn(TARGET_TAG, source.name)
    if replacements != 1:
        raise SystemExit(f"expected exactly one iOS device tag in {source.name}")

    with zipfile.ZipFile(source, "r") as archive:
        entries = {info.filename: archive.read(info.filename) for info in archive.infolist()}

    wheel_paths = [name for name in entries if name.endswith(".dist-info/WHEEL")]
    record_paths = [name for name in entries if name.endswith(".dist-info/RECORD")]
    if len(wheel_paths) != 1 or len(record_paths) != 1:
        raise SystemExit("wheel must contain exactly one WHEEL and one RECORD")

    wheel_path = wheel_paths[0]
    record_path = record_paths[0]
    wheel_text = entries[wheel_path].decode("utf-8")
    wheel_text, tag_replacements = IOS_TAG_RE.subn(TARGET_TAG, wheel_text)
    if tag_replacements < 1:
        raise SystemExit("WHEEL metadata did not contain an iOS device platform tag")
    entries[wheel_path] = wheel_text.encode("utf-8")

    rows = []
    reader = csv.reader(io.StringIO(entries[record_path].decode("utf-8")))
    for row in reader:
        if not row:
            continue
        while len(row) < 3:
            row.append("")
        path = row[0]
        if path == record_path:
            row[1] = ""
            row[2] = ""
        elif path in entries:
            row[1] = digest(entries[path])
            row[2] = str(len(entries[path]))
        rows.append(row)

    record_buffer = io.StringIO(newline="")
    writer = csv.writer(record_buffer, lineterminator="\n")
    writer.writerows(rows)
    entries[record_path] = record_buffer.getvalue().encode("utf-8")

    destination = dest_dir / new_name
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)

    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
