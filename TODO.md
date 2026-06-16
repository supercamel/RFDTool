# RFDTool TODO

Build a GTK4/SQGI utility for configuring an RFD900-class radio modem on
`/dev/ttyUSB0`, using `GSerial` as the serial-port native module.

## Research Notes

- RFD900/RFD900x radios use SiK-derived firmware and expose a Hayes-style AT
  command interface for configuration.
- Default serial settings for the Point-to-Point/SiK firmware are `57600` baud,
  no parity, 8 data bits, 1 stop bit.
- Enter command mode by leaving at least one second of idle serial time, sending
  `+++`, then waiting for `OK`.
- Use `AT...` commands for the local modem and `RT...` commands for the remote
  modem. Some legacy/multipoint firmware variants accept an optional node id
  suffix such as `RTI,1`.
- Use `ATI5` to read user-settable parameters and `ATI5?` to read available
  ranges. The utility should parse these dynamically so it can support different
  RFD900, RFD900u, RFD900+, RFD900x, and firmware variants.
- Change S-register values with `ATSn=X`, query them with `ATSn?`, save staged
  settings with `AT&W`, and reboot with `ATZ` when required. Use the `RT`
  equivalents for remote radios.
- Parameters that usually must match on both ends include network id, air speed,
  frequency range, channel count, ECC, some listen-before-talk settings, and
  encryption level/key. Changing one side first can intentionally break the link
  until the other side matches.
- Core status/diagnostic commands to support include `ATI`, `ATI1` through
  `ATI9`, `ATI5`, `ATI5?`, `ATI6`, `ATI7`, `ATO`, `AT&T`, `AT&T=RSSI`,
  `AT&T=TDM`, `AT&P`, `AT&F`, `AT&W`, `ATZ`, and `AT&UPDATE`.
- GPIO commands to support include `ATPP`, `ATPI=X`, `ATPO=X`, `ATPM=X`,
  `ATPR=X`, and `ATPC=X,S`, plus `RT` equivalents.
- Encryption is configured with `S15` and `AT&E=...`; RFD900x V3 firmware allows
  128-bit or 256-bit AES keys depending on encryption level and firmware/region.
- Typical important registers seen in RFD900/RFD900x documentation:
  `S1 SERIAL_SPEED`, `S2 AIR_SPEED`, `S3 NETID`, `S4 TXPOWER`, `S5 ECC`,
  `S6 MAVLINK`, `S7 OP_RESEND`, `S8 MIN_FREQ`, `S9 MAX_FREQ`,
  `S10 NUM_CHANNELS`, `S11 DUTY_CYCLE`, `S12 LBT_RSSI`, `S13 RTSCTS`,
  plus newer x-series fields such as `S14 Max Window`, `S15 Encryption Level`,
  `S16` through `S19` RC/SBUS options, `S20 ANT_MODE`, `S21` status LED,
  `S22` RS485/DINIO control, `S23` certified rate/frequency band, `S24/S25`
  auxiliary serial pins, `S28 FSFRAMELOSS`, and `R0/R1` dynamic power control.
- Air-speed options and register meanings vary by model, firmware, region lock,
  and certified modem settings. Never hard-code only one parameter table.
- Lower air data rates can improve range but reduce throughput; flow control and
  serial baud choices matter. The UI should explain bottleneck risks through
  validation/status text near the affected controls, not by silently accepting
  risky combinations.
- Region-certified modems restrict country, frequency, power, and allowed rates.
  The tool must show the detected region/country from `ATI` and refuse to bypass
  certified restrictions.
- GSerial provides a GObject-introspectable `GSerial.Port` with `open`, `close`,
  `read_string`, `read_bytes`, `read_line`, `write_string`, `write_bytes`,
  `bytes_available`, serial-format setters, and `connected`, `disconnected`,
  `on_data` signals.

Reference material:

- ArduPilot RFD900 overview:
  https://ardupilot.org/copter/docs/common-rfd900.html
- PX4 SiK radio integration notes:
  https://docs.px4.io/main/en/data_links/sik_radio
- GSerial repository:
  https://github.com/supercamel/gserial
- SQGI examples/docs:
  `/home/sam/Programming/sqgi/demo/gtk4`,
  `/home/sam/Programming/sqgi/docs/packaging`

## Project Bootstrap

- [ ] Create `sqgipkg.json` with `name`, `script`, `script_dirs`, Linux target
  defaults, and Windows metadata placeholders.
- [ ] Add `gserial` to the `sqgipkg` manifest as a native project cloned from
  `https://github.com/supercamel/gserial`, with pinned `tag`, `ref`, or commit
  once selected.
- [ ] Configure the native project to build with Meson and stage
  `libgserial-1.0.so` plus `GSerial-1.0.typelib`.
- [ ] Add a local-development path that can use the already-installed
  `/usr/lib/aarch64-linux-gnu/libgserial-1.0.so` and
  `/usr/lib/aarch64-linux-gnu/girepository-1.0/GSerial-1.0.typelib`.
- [ ] Create `main.nut` and initial source layout:
  `src/app.nut`, `src/ui/window.nut`, `src/serial/port.nut`,
  `src/rfd/commands.nut`, `src/rfd/parser.nut`, `src/rfd/model.nut`,
  `src/rfd/session.nut`, and `src/rfd/validation.nut`.
- [ ] Add a `README.md` with install/run instructions, default device path, and
  a clear warning about legal/regulatory compliance for RF settings.
- [ ] Add `.gitignore` for SQGI build/dist output and temporary modem captures.

## Serial Transport

- [ ] Import `Gtk 4.0`, `Gio`, `GLib`, and `GSerial 1.0` from SQGI.
- [ ] Build a `SerialPort` wrapper around `GSerial.Port`.
- [ ] Default to `/dev/ttyUSB0`, `57600`, 8N1, timeout appropriate for command
  mode, and no flow control unless a future GSerial API exposes RTS/CTS.
- [ ] Support selecting another `/dev/ttyUSB*`, `/dev/ttyACM*`, or manually
  typed device path.
- [ ] Buffer incoming data from `on_data` and normalize line endings.
- [ ] Expose asynchronous request/response operations with timeouts,
  cancellation, retry limits, and clean error propagation.
- [ ] Add raw terminal logging for sent/received bytes while hiding encryption
  keys by default.
- [ ] Ensure reads and writes are serialized so a user terminal command cannot
  collide with automated parameter loading.
- [ ] Handle disconnect, permission-denied, busy-port, and stale-device errors.
- [ ] Verify whether GSerial's timeout is milliseconds or microseconds in the
  installed build, then document and wrap it consistently.

## RFD Command Session

- [ ] Implement a command-mode state machine:
  idle guard, send `+++`, wait for `OK`, set state to command mode.
- [ ] Implement `ATO` to leave command mode and return to transparent mode.
- [ ] Implement basic command sending with `\r\n` termination and prompt/result
  parsing.
- [ ] Add local and remote command prefixes so the same command model can call
  `AT...` or `RT...`.
- [ ] Implement firmware discovery:
  `ATI`, `ATI1`, `ATI2`, `ATI3`, `ATI4`, `ATI8`, optional `ATI9`.
- [ ] Parse the `ATI` region suffix such as `-AU`, `-NZ`, `-US`, `-EU`, `-IN`,
  and mark unlocked modems explicitly.
- [ ] Load current parameters with `ATI5`.
- [ ] Load parameter ranges with `ATI5?`.
- [ ] Query single registers with `ATS<n>?`, `ATR<n>?`, `RTS<n>?`, and
  `RTR<n>?`.
- [ ] Set S-register and R-register values with staged commands, but do not
  save until the user chooses Save.
- [ ] Save settings with `AT&W`/`RT&W`.
- [ ] Reboot with `ATZ`/`RTZ` and automatically reconnect after the serial device
  recovers.
- [ ] Implement factory reset via `AT&F`/`RT&F` behind a confirmation dialog.
- [ ] Implement bootloader/update entry via `AT&UPDATE` behind a stronger
  confirmation dialog and leave actual firmware flashing for a later phase.
- [ ] Implement diagnostics for `ATI6`, `ATI7`, `AT&T=RSSI`, `AT&T=TDM`, and
  `AT&T` disable.
- [ ] Implement GPIO command helpers for print, input, output, mirror, read, and
  write state operations.
- [ ] Implement encryption key read/write helpers around `AT&E?` and `AT&E=...`
  with careful masking in logs and UI.
- [ ] Support legacy multipoint node-addressed remote forms such as `RTI,1` if
  detected or manually enabled.

## Parameter Model And Validation

- [ ] Represent every modem parameter as a structured object:
  register class (`S`/`R`), number, name, value, default, min, max, enum choices,
  description, match-required flag, firmware notes, and dirty state.
- [ ] Prefer live metadata parsed from `ATI5?`; fall back to a documented
  built-in table for common RFD900/RFD900x parameters.
- [ ] Keep fallback tables versioned by firmware family:
  legacy RFD900 SiK, RFD900 multipoint, RFD900x V3 Point-to-Point, and future
  async/multipoint variants.
- [ ] Validate numeric ranges before sending commands.
- [ ] Validate discrete choices for serial speed, air speed, antenna mode, SBUS
  mode, encryption level, and boolean settings.
- [ ] Mark settings that must match both radios and warn before saving only one
  side.
- [ ] Warn when frequency/power/band choices appear restricted by the detected
  region lock.
- [ ] Warn when serial speed, air speed, MAVLink, ECC, flow control, or duty
  cycle choices can create throughput or reliability problems.
- [ ] Treat `S0 FORMAT` and reserved registers as read-only.
- [ ] Treat `S8`, `S9`, `S10`, `S12`, `S23`, and power/frequency fields as
  high-risk when region-certified.
- [ ] Track staged local and remote changes independently.
- [ ] Provide rollback by reloading values from the modem before save.
- [ ] Generate a command preview before applying changes.

## GTK4 User Interface

- [ ] Build the first screen as the actual utility, not a landing page.
- [ ] Use a compact, work-focused GTK4 layout suitable for repeated modem
  configuration.
- [ ] Header area:
  device path combo/entry, baud selector, Connect button, command-mode state,
  local/remote link status, firmware summary, and region badge.
- [ ] Main navigation:
  Overview, Parameters, Radio Link, Serial, GPIO, Diagnostics, Terminal, and
  Apply tabs.
- [ ] Overview tab:
  firmware, board type, board frequency, board version, unique id, region,
  current link RSSI/noise when available, and save/reboot status.
- [ ] Parameters tab:
  searchable/filterable parameter table with register, name, local value,
  remote value, allowed range, match-required marker, dirty marker, and notes.
- [ ] Radio Link tab:
  network id, air speed, TX power, min/max frequency, channel count, duty cycle,
  listen-before-talk, antenna mode, ECC, MAVLink, and opportunistic resend.
- [ ] Serial tab:
  serial baud, RTS/CTS register, flow-control warnings, and reconnect workflow
  after changing baud.
- [ ] Encryption panel:
  encryption level selector, masked key entry, random-key generation,
  show/hide toggle, copy-local-to-remote action, and warning when only one side
  is changed.
- [ ] GPIO tab:
  pin list, input/output mode controls, mirror setup, current state, and output
  state toggles.
- [ ] Diagnostics tab:
  run `ATI6`, `ATI7`, start/stop RSSI debug, start/stop TDM debug, export
  diagnostic log.
- [ ] Terminal tab:
  raw command input, scrollback, optional echo, and a lockout indicator when the
  app is running automated commands.
- [ ] Apply tab:
  staged changes grouped by local/remote, risk warnings, command preview,
  Apply, Save to EEPROM, Save + Reboot, Revert, Factory Reset.
- [ ] Use icons for connect/disconnect, refresh, save, reboot, reset, warning,
  terminal, copy, randomize, show/hide key, import/export, and log clear.
- [ ] Provide responsive sizing for small laptop screens; avoid overlapping
  labels and controls.
- [ ] Use GTK CSS sparingly for a restrained instrument-panel look.
- [ ] Preserve enough terminal/log context for troubleshooting failed command
  mode entry.

## Apply/Save Workflows

- [ ] Implement Refresh Local and Refresh Remote.
- [ ] Implement Apply Local Only, Apply Remote Only, and Apply Both.
- [ ] For match-required settings, recommend applying remote first, then local,
  because a remote mismatch can drop the link.
- [ ] For serial baud changes, save, reboot, close the port, reopen at the new
  baud, and verify with `ATI`.
- [ ] For frequency/network/encryption changes, show a "link may drop" dialog
  and guide the user through applying the other side.
- [ ] After save/reboot, wait for reboot, re-enter command mode, reload
  parameters, and compare expected versus actual values.
- [ ] Provide a "dry run" command preview mode that sends nothing.
- [ ] Provide export/import profiles as JSON.
- [ ] Include metadata in profiles:
  firmware, board, region, timestamp, local/remote, and app version.
- [ ] Refuse to import profiles that attempt unknown, reserved, read-only, or
  out-of-range registers unless the user explicitly enables expert mode.

## Testing

- [ ] Build a fake serial transport for unit tests and UI smoke tests.
- [ ] Add parser tests for:
  `OK`, `ERROR`, `ATI` firmware strings, `ATI5` tables, `ATI5?` ranges,
  single-register queries, RSSI reports, TDM reports, and GPIO output.
- [ ] Add state-machine tests for command-mode entry timing, retries, timeout,
  disconnect, and reboot/reconnect.
- [ ] Add validation tests for known RFD900/RFD900x registers and region-locked
  constraints.
- [ ] Add tests for command preview generation and correct local/remote command
  prefixes.
- [ ] Add log-redaction tests for encryption keys.
- [ ] Add profile import/export round-trip tests.
- [ ] Add a headless GTK smoke test that opens the app, connects to fake
  transport, loads fake parameters, edits one value, previews commands, and
  exits.
- [ ] Add a hardware smoke-test checklist for `/dev/ttyUSB0`:
  open port, enter command mode, run `ATI`, run `ATI5`, exit with `ATO`.
- [ ] Add a hardware write-test checklist that changes a harmless reversible
  parameter, saves, reboots, verifies, then restores.

## Packaging And Distribution

- [ ] Run `sqgipkg --doctor`.
- [ ] Run `sqgipkg --smoke-test ""`.
- [ ] Verify packaged app can import `GSerial 1.0`.
- [ ] Verify packaged app can import GTK4 and open the main window.
- [ ] Include `gserial` library and typelib in Linux AppImage output.
- [ ] Add Linux udev/permissions documentation for serial ports, including
  `dialout` group membership.
- [ ] Decide whether firmware flashing will be supported later or intentionally
  delegated to RFD Modem Tools.
- [ ] If Windows packaging is pursued, configure MSYS2 build/dependency entries
  for GTK4, GObject Introspection, and GSerial.

## Documentation

- [ ] Document all supported RFD commands and which UI surface uses them.
- [ ] Document parameter table source: live `ATI5?` when available, fallback
  table otherwise.
- [ ] Document local versus remote safety rules.
- [ ] Document how to recover if baud, net id, frequency, or encryption changes
  break communication.
- [ ] Document regulatory responsibilities around power and frequency.
- [ ] Document known firmware differences and unsupported fields.
- [ ] Document how to capture logs for bug reports without leaking encryption
  keys.

## Open Questions

- [ ] Which exact hardware/firmware is on `/dev/ttyUSB0`: legacy RFD900,
  RFD900u/+, RFD900x/ux, peer-to-peer, multipoint, or asynchronous?
- [ ] Should the first release support only Point-to-Point/SiK firmware, or also
  multipoint/async UI affordances?
- [ ] Should firmware update/upload be in scope after configuration is stable?
- [ ] Do we need expert-mode access to raw/unknown registers, or should unknown
  registers remain read-only until modeled?
- [ ] Should profiles be compatible with Mission Planner/RFD Tools formats if
  those formats are practical to reverse or document?
