# RFDTool

RFDTool is a GTK 4 utility for inspecting and configuring RFD900-class radio
modems through the SiK/RFD AT command interface.

It is written in SQGI/Squirrel and uses the GSerial native module for serial
port access.

## Downloads

Prebuilt binaries are attached to each [GitHub release](../../releases):

- `RFDTool-x86_64.AppImage` — Linux on Intel/AMD 64-bit.
- `RFDTool-aarch64.AppImage` — Linux on ARM 64-bit (e.g. Raspberry Pi OS 64-bit).
- `RFDTool-Setup.exe` — Windows installer.

Make an AppImage executable before running it:

```sh
chmod +x RFDTool-x86_64.AppImage
./RFDTool-x86_64.AppImage
```

Releases are produced by the `.github/workflows/release.yml` GitHub Actions
workflow, which builds all three targets with `sqgipkg` and uploads them when a
`v*` tag is pushed.

## Features

- Connect to local RFD/SiK radios over a serial port.
- Read local and remote firmware information.
- Read, edit, stage, apply, save, and reboot supported modem parameters.
- Show which settings are reported by the connected firmware.
- Configure AES keys, including generating random 128-bit or 256-bit keys.
- Run RSSI/TDM diagnostics and graph RSSI/noise over a rolling 60 second window.
- Export and import JSON configuration profiles.

## Running From Source

Running directly with `sqgi main.nut` requires both SQGI and GSerial to be
installed on the system.

Install SQGI from https://github.com/supercamel/sqgi:

```sh
git clone https://github.com/supercamel/sqgi.git
cd sqgi

sudo apt install cmake build-essential pkg-config \
  libglib2.0-dev libgirepository1.0-dev libffi-dev libcairo2-dev

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
sudo cmake --install build --prefix /usr/local
```

Install GSerial from https://github.com/supercamel/gserial:

```sh
git clone https://github.com/supercamel/gserial.git
cd gserial

sudo apt install build-essential meson ninja-build pkg-config \
  libglib2.0-dev libgirepository1.0-dev

meson setup build --prefix=/usr/local
meson compile -C build
sudo meson install -C build
sudo ldconfig
```

Install GTK 4 runtime/introspection packages if they are not already present:

```sh
sudo apt install libgtk-4-1 gir1.2-gtk-4.0
```

Then run RFDTool:

```sh
git clone https://github.com/supercamel/RFDTool.git
cd RFDTool
sqgi main.nut
```

The default serial device is `/dev/ttyUSB0` at `57600` baud.

## Useful Commands

Run the self-tests:

```sh
sqgi main.nut --self-test
```

Probe a local modem without launching the GUI:

```sh
sqgi main.nut --probe --device=/dev/ttyUSB0 --baud=57600
```

Exercise the local settings load path from the command line:

```sh
sqgi main.nut --refresh-local --device=/dev/ttyUSB0 --baud=57600
```

## Packaging

The `sqgipkg.json` manifest declares GSerial as a native project:

```json
"repo": "https://github.com/supercamel/gserial.git"
```

That means packaged builds can fetch and build GSerial through `sqgipkg`; the
GSerial checkout under `.sqgipkg/native/` is generated build state and is not
committed to this repository.

The manifest defines a `linux.arches` matrix (x86_64 and aarch64) plus a Windows
target, so every artifact can be cross-built from a single Linux host:

```sh
sqgipkg --doctor
sqgipkg --target appimage --appimage-arch x86_64
sqgipkg --target appimage --appimage-arch aarch64
sqgipkg --target win-nsis
```

The aarch64 and Windows targets are cross-compiled. On an x86_64 Ubuntu host they
need the cross toolchains:

```sh
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu qemu-user-static \
  mingw-w64 nsis
```

`sqgipkg` downloads the matching sysroots, builds the SQGI runtime and GSerial
for each target, and writes the AppImages and the NSIS installer under
`dist-linux-x86_64/`, `dist-linux-aarch64/`, and `dist-windows-x86_64/`.

## Serial Permissions

On Linux, serial devices are commonly owned by a group such as `dialout`.
If RFDTool cannot open the modem, check the device ownership:

```sh
ls -l /dev/ttyUSB0
id
```

Add the user to the device group, then log out and back in:

```sh
sudo usermod -aG dialout "$USER"
```

Use the actual group shown by `ls -l` if the device is not owned by `dialout`.

## Safety

Radio settings are regulated. Do not use this tool to bypass certified
frequency, region, duty-cycle, or transmit-power limits.

Some settings need to match on both radios, including network id, air speed,
frequency range, channel count, ECC, MAVLink framing, and encryption. Changing
only one side can intentionally break the link until the other side is updated.
