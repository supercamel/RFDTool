#!/usr/bin/env python3
"""Run production smoke, responsive layout, and JNI serial tests on an emulator."""
import argparse
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--adb", default="adb")
parser.add_argument("--serial", default="emulator-5564")
parser.add_argument("--output", default="build-android-checks")
args = parser.parse_args()
if not args.serial.startswith("emulator-"):
    parser.error("Use an emulator: this test changes its screen size and density")
output = Path(args.output)
output.mkdir(parents=True, exist_ok=True)


def adb(*command):
    return subprocess.check_output([args.adb, "-s", args.serial, *command], timeout=60).decode().strip()


def start(app):
    adb("shell", "am", "force-stop", app)
    adb("logcat", "-c")
    adb("shell", "am", "start", "-W", "-n", f"{app}/org.sqgi.android.GtkActivity")


def wait_for(app, marker, name):
    start(app)
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        logs = adb("logcat", "-d", "-v", "brief")
        if any(error in logs for error in ("RFDTOOL_LAYOUT_FAIL", "RFDTOOL_ANDROID_SERIAL_FAIL",
                                          "AN ERROR HAS OCCURRED", "Fatal signal", "FATAL EXCEPTION")):
            break
        if marker in logs:
            # Include asynchronous surface teardown, not just the success print.
            time.sleep(1)
            logs = adb("logcat", "-d", "-v", "brief")
            if any(error in logs for error in ("AN ERROR HAS OCCURRED", "Fatal signal", "FATAL EXCEPTION")):
                break
            (output / f"{name}.log").write_text(logs)
            print(f"{name}: {marker}", flush=True)
            return
        time.sleep(1)
    (output / f"{name}.log").write_text(logs)
    print("\n".join(line for line in logs.splitlines() if any(
        marker in line for marker in ("SqgiAndroid", app, "FATAL", "Fatal", "ANR", "libc", "Gtk-")
    ))[-3000:], flush=True)
    raise AssertionError(f"{name} failed; see {output / (name + '.log')}")


def override(kind):
    lines = adb("shell", "wm", kind).splitlines()
    return next((line.split(": ", 1)[1] for line in lines if line.startswith("Override")), "reset")


original_size, original_density = override("size"), override("density")
try:
    for apk in [
        "dist-android-x86_64/com.github.supercamel.rfdtool-x86_64-debug.apk",
        "dist-android-layout-test/com.github.supercamel.rfdtool.layouttest-x86_64-debug.apk",
        "dist-android-test/com.github.supercamel.rfdtool.serialtest-x86_64-debug.apk",
    ]:
        adb("install", "-r", apk)
    for name, size, density in [
        ("phone-portrait", "720x1280", "320"),
        ("phone-landscape", "1280x720", "320"),
        ("tablet-portrait", "1200x1920", "240"),
        ("tablet-landscape", "1920x1200", "240"),
    ]:
        adb("shell", "wm", "size", size)
        adb("shell", "wm", "density", density)
        time.sleep(2)
        start("com.github.supercamel.rfdtool")
        time.sleep(3)
        adb("shell", "pidof", "com.github.supercamel.rfdtool")
        logs = adb("logcat", "-d", "-v", "brief")
        assert not any(error in logs for error in ("AN ERROR HAS OCCURRED", "FATAL EXCEPTION", "Fatal signal")), logs
        with (output / f"{name}.png").open("wb") as image:
            subprocess.run([args.adb, "-s", args.serial, "exec-out", "screencap", "-p"], stdout=image, check=True, timeout=30)
        adb("shell", "am", "force-stop", "com.github.supercamel.rfdtool")
        wait_for("com.github.supercamel.rfdtool.layouttest", "RFDTOOL_LAYOUT_PASS", name)
    wait_for("com.github.supercamel.rfdtool.serialtest", "RFDTOOL_ANDROID_SERIAL_PASS", "serial")
finally:
    for app in ["com.github.supercamel.rfdtool", "com.github.supercamel.rfdtool.layouttest", "com.github.supercamel.rfdtool.serialtest"]:
        adb("shell", "am", "force-stop", app)
    adb("shell", "wm", "size", original_size)
    adb("shell", "wm", "density", original_density)
print("ANDROID_CHECKS_PASS")
