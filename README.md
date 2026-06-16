# RFDTool

<p align="center">
  <img src="images/com.github.supercamel.rfdtool.png" alt="RFDTool logo" width="128" height="128">
</p>

RFDTool is a desktop utility for inspecting and configuring RFD900-class and
SiK-compatible radio modems. It talks to a locally connected modem over serial,
then can read and configure both the local radio and the remote radio across the
radio link.

Use it when you want a clearer, safer interface than typing AT commands by hand.

## Download

Prebuilt binaries are attached to the
[latest GitHub release](../../releases/latest):

- `RFDTool-x86_64.AppImage` for Linux on Intel/AMD 64-bit.
- `RFDTool-aarch64.AppImage` for Linux on ARM 64-bit, such as Raspberry Pi OS 64-bit.
- `RFDTool-Setup.exe` for Windows.

The ARM AppImage should work on Raspberry Pi-class boards running a 64-bit Linux
desktop. It has been tested on an Orange Pi running Ubuntu 24.04.

On Linux, make the AppImage executable before running it:

```sh
chmod +x RFDTool-x86_64.AppImage
./RFDTool-x86_64.AppImage
```

On Windows, download and run `RFDTool-Setup.exe`.

The default serial device is `/dev/ttyUSB0` at `57600` baud.

## Quick Start

1. Plug the local radio modem into your computer.
2. Power the remote radio and make sure the radio link is up.
3. Start RFDTool.
4. Choose the serial port and baud rate, then connect.
5. Click the local and remote refresh buttons to read firmware and settings.
6. Edit the settings you need.
7. Use `Apply Local` or `Apply Remote` to write changes to the running radio.
8. Use `Save Both` to persist applied changes to EEPROM.
9. Use `Save + Reboot` when firmware or radio-critical settings need a restart.

If you are changing settings that must match on both radios, apply the remote
side first. If the link drops after changing only the local side, RFDTool may no
longer be able to reach the remote radio.

## Local, Remote, Apply, Save

RFDTool shows the two sides separately:

- Local is the modem connected directly to your computer.
- Remote is the modem reached through the radio link.

RFD and SiK firmware make an important distinction between applying and saving:

- `Apply` writes the setting into the running radio.
- `Save` writes the current settings to EEPROM so they survive power loss.
- `Reboot` restarts the modem so startup-time settings take effect.

For remote changes, RFDTool sends `RT...` commands through the local modem. That
requires a working radio link and can take longer than local `AT...` commands,
especially after rebooting the remote radio.

## Features

- Connect to local RFD/SiK radios over a serial port.
- Read local and remote firmware information.
- Read, edit, stage, apply, save, and reboot supported modem parameters.
- Show which settings are reported by the connected firmware.
- Configure AES keys, including generated random 128-bit or 256-bit keys.
- Run RSSI/TDM diagnostics and graph RSSI/noise over a rolling 60 second window.
- Export and import JSON configuration profiles.
- Send manual AT commands from the built-in terminal.

## Troubleshooting

If RFDTool cannot open the serial port on Linux, check the device ownership:

```sh
ls -l /dev/ttyUSB0
id
```

Serial devices are commonly owned by a group such as `dialout`. Add your user to
the device group, then log out and back in:

```sh
sudo usermod -aG dialout "$USER"
```

Use the actual group shown by `ls -l` if the device is not owned by `dialout`.

If local refresh works but remote refresh does not, check that the remote radio
is powered, the antennas are connected, and both radios still agree on link
settings such as network ID, air speed, frequency range, channel count, ECC,
MAVLink framing, and encryption.

If a setting change breaks the radio link, connect to the affected radio directly
over serial and restore compatible settings.

## Safety

Radio settings are regulated. Do not use this tool to bypass certified
frequency, region, duty-cycle, or transmit-power limits.

Some settings need to match on both radios, including network ID, air speed,
frequency range, channel count, ECC, MAVLink framing, and encryption. Changing
only one side can intentionally break the link until the other side is updated.

## Developers

RFDTool is written in SQGI/Squirrel, uses GTK 4 for the interface, and uses the
GSerial native module for serial port access.

### Running From Source

Running directly with `sqgi main.nut` requires SQGI, GSerial, and GTK 4 runtime
packages to be installed on the system.

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

### Useful Commands

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

### Packaging

The `sqgipkg.json` manifest declares GSerial as a native project:

```json
"repo": "https://github.com/supercamel/gserial.git"
```

That means packaged builds can fetch and build GSerial through `sqgipkg`; the
GSerial checkout under `.sqgipkg/native/` is generated build state and is not
committed to this repository.

The manifest defines a `linux.arches` matrix for x86_64 and aarch64 plus a
Windows target, so every artifact can be cross-built from a single Linux host:

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

Releases are produced by the `.github/workflows/release.yml` GitHub Actions
workflow, which builds all three targets with `sqgipkg` and uploads them when a
`v*` tag is pushed.
