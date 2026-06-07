# RFDTool

RFDTool is a GTK4/SQGI utility for inspecting and configuring RFD900-class
radio modems through the SiK/RFD AT command interface.

The current default target is an RFD900 modem on `/dev/ttyUSB0` at `57600`
baud, 8 data bits, no parity, and 1 stop bit. The app uses `GSerial 1.0` for
native serial-port access.

## Requirements

- SQGI and `sqgipkg` from https://github.com/supercamel/sqgi
- GTK 4 runtime and introspection data
- Serial-port permission for the modem device, usually via the `dialout` group

The `sqgipkg.json` manifest pulls `https://github.com/supercamel/gserial.git`
as a native project. Do not commit `.sqgipkg/native/gserial`; `sqgipkg` will
clone and build it from the manifest.

## Run

```sh
sqgi main.nut
```

Useful non-GUI checks:

```sh
sqgi main.nut --self-test
sqgi main.nut --probe --device=/dev/ttyUSB0 --baud=57600
sqgi main.nut --refresh-local --device=/dev/ttyUSB0 --baud=57600
```

`--probe` is read-oriented: it opens the port, enters command mode, runs `ATI`
and `ATI5`, exits command mode, and closes the port.

## Build

```sh
sqgipkg --doctor
sqgipkg --target appimage --smoke-test "--self-test"
```

Packaged builds include `libgserial-1.0.so` and `GSerial-1.0.typelib` from the
native project declared in `sqgipkg.json`.

## Tests

```sh
sqgi test/parser_tests.nut
sqgi test/session_tests.nut
sqgi main.nut --self-test
```

## Serial Permissions

On this machine, user `sam` is in the `dialout` group and `/dev/ttyUSB0` is
`root:dialout` with group read/write permission, so the tool should not need
`sudo`.

If another system cannot open the modem, check:

```sh
id
ls -l /dev/ttyUSB0
```

Then add the user to the serial-port group used by that device, commonly
`dialout`, and log out/in.

## Safety

Radio settings are regulated. The tool should display firmware region/country
information and must not be used to bypass certified frequency or power limits.

Settings such as network id, air speed, frequency range, channel count,
listen-before-talk, ECC, and encryption generally need to match on both radios.
Changing only one side may intentionally break the link until the other side is
configured to match.
