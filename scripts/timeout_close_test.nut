local GLib = import("GLib")
local SerialMod = import("../src/serial/port.nut")
local SessionMod = import("../src/rfd/session.nut")

local device = vargv.len() > 0 ? vargv[0] : "/dev/ttyUSB0"
local baud = vargv.len() > 1 ? vargv[1].tointeger() : 57600
local loop = GLib.MainLoop.new(null, false)

async function run() {
    local serial = SerialMod.SerialPort()
    serial.set_log_callback(function(entry) {
        print("[" + entry.time + "] " + entry.direction + " " + entry.text + "\n")
    })

    if (!serial.open(device, baud)) throw "failed to open " + device
    local session = SessionMod.RfdSession(serial)

    try {
        await session.enter_command_mode()
        print("entered command mode; closing cleanly\n")
    } catch (e) {
        print("command-mode attempt ended: " + e + "\n")
    }

    serial.close()
    print("closed serial; keeping loop alive to drain native poll source\n")
    await sqgi.sleep(300)
    loop.quit()
}

run().catch(function(e) {
    print("timeout-close test error: " + e + "\n")
    loop.quit()
})

loop.run()
print("[OK] timeout-close test exited normally\n")
