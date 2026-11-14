#!/usr/bin/env python3
"""Exercise the GTK Connect/Refresh path through a real GSerial Linux PTY."""
import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import time

root = Path(__file__).resolve().parents[1]
master, slave = pty.openpty()
commands = []
process = subprocess.Popen(
    ["sqgi", "main.nut", "--gtk-refresh-local-test", f"--device={os.ttyname(slave)}"],
    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
)
buffer = b""
deadline = time.monotonic() + 30
try:
    while process.poll() is None and time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.05)
        if not ready:
            continue
        try:
            buffer += os.read(master, 4096)
        except OSError as error:
            if error.errno == errno.EIO:
                continue
            raise
        while b"\n" in buffer:
            raw, buffer = buffer.split(b"\n", 1)
            command = raw.strip().decode()
            commands.append(command)
            if command == "ATI":
                body = "RFD SiK 3.16 on RFD900x R1.3-AU"
            elif command == "ATI5":
                body = "S1:SERIAL_SPEED=57\r\nS2:AIR_SPEED=64\r\nS3:NETID=23\r\nS4:TXPOWER=20"
            elif command == "ATI5?":
                body = "S1:SERIAL_SPEED=57 1..1000\r\nS2:AIR_SPEED=64 2..750\r\nS3:NETID=23 0..255\r\nS4:TXPOWER=20 0..30"
            else:
                body = "" if command == "AT" else "test"
            os.write(master, (command + "\r\n" + body + "\r\nOK\r\n").encode())
    if process.poll() is None:
        process.kill()
        raise AssertionError("GTK serial test timed out")
    output = process.communicate(timeout=5)[0]
    print(output)
    assert process.returncode == 0, process.returncode
    assert "[gtk-test] error:" not in output and "AN ERROR HAS OCCURRED" not in output
    assert "AT" in commands and "ATI5" in commands and "ATI5?" in commands, commands
    print("GTK_SERIAL_PASS: real serial open, command mode, settings refresh, and window cleanup")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    os.close(slave)
