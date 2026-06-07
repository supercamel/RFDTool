local GLib = import("GLib")
local U = import("../src/util.nut")
local SessionMod = import("../src/rfd/session.nut")
local Model = import("../src/rfd/model.nut")

function check(name, cond) {
    if (!cond) throw "[FAIL] " + name
    print("[PASS] " + name + "\n")
}

class FakeSerial {
    buffer = ""
    writes = null
    open = true

    constructor() {
        writes = []
    }

    function is_open() { return open }
    function clear_buffer() { buffer = "" }
    function get_buffer() { return buffer }

    function respond(text) {
        local self = this
        sqgi.timeout_add(5, function() {
            self.buffer += text
            return false
        })
    }

    function write(text) {
        writes.append(text)
        local cmd = U.trim(text)
        if (cmd == "+++") {
            respond("OK\r\n")
        } else if (cmd == "ATI") {
            respond("ATI\r\nRFD SiK 3.16 on RFD900x R1.3-AU\r\nOK\r\n")
        } else if (cmd == "ATI1" || cmd == "ATI2" || cmd == "ATI3" ||
            cmd == "ATI4" || cmd == "ATI6" || cmd == "ATI7" ||
            cmd == "ATI8" || cmd == "ATI9") {
            respond(cmd + "\r\nvalue for " + cmd + "\r\nOK\r\n")
        } else if (cmd == "ATI5") {
            respond("ATI5\r\nS1:SERIAL_SPEED=57\r\nS2:AIR_SPEED=64\r\nS3:NETID=23\r\nOK\r\n")
        } else if (cmd == "ATI5?") {
            respond("ATI5?\r\nS1:SERIAL_SPEED=57 1..1000\r\nS2:AIR_SPEED=64 2..750\r\nS3:NETID=23 0..255\r\nOK\r\n")
        } else if (cmd == "ATS3=24") {
            respond("ATS3=24\r\nOK\r\n")
        } else if (cmd == "AT&W") {
            respond("AT&W\r\nOK\r\n")
        } else if (cmd == "ATZ") {
            respond("ATZ\r\n")
        } else if (cmd == "AT&T=RSSI") {
            respond("AT&T=RSSI\r\n")
        } else if (cmd == "AT&T=TDM") {
            respond("AT&T=TDM\r\n")
        } else if (cmd == "AT&T") {
            respond("AT&T\r\n")
        } else if (cmd == "ATO") {
            respond("ATO\r\nOK\r\n")
        } else {
            respond(cmd + "\r\nERROR\r\n")
        }
        return text.len()
    }
}

local loop = GLib.MainLoop.new(null, false)

async function run() {
    local serial = FakeSerial()
    local session = SessionMod.RfdSession(serial)
    await session.enter_command_mode()
    check("entered command mode", session.in_command_mode)

    local loaded = await session.load_side("local")
    check("load firmware", loaded.summary.firmware.region == "AU")
    check("load params", loaded.params.S3.value == 23)

    local meta = Model.fallback_metadata().S3
    await session.set_register("local", meta, 24)
    check("set command emitted", serial.writes.find("ATS3=24\r\n") != null)

    await session.save("local")
    check("save command emitted", serial.writes.find("AT&W\r\n") != null)

    await session.reboot("local")
    check("reboot command emitted", serial.writes.find("ATZ\r\n") != null)
    check("reboot leaves command mode", !session.in_command_mode)

    await session.enter_command_mode()
    check("re-entered after reboot", session.in_command_mode)

    await session.diagnostics("local", "rssi")
    check("RSSI debug command emitted", serial.writes.find("AT&T=RSSI\r\n") != null)
    await session.diagnostics("local", "tdm")
    check("TDM debug command emitted", serial.writes.find("AT&T=TDM\r\n") != null)
    await session.diagnostics("local", "stop")
    check("debug stop command emitted", serial.writes.find("AT&T\r\n") != null)

    await session.leave_command_mode()
    check("left command mode", !session.in_command_mode)
    loop.quit()
}

run().catch(function(e) {
    print("session test error: " + e + "\n")
    loop.quit()
})
loop.run()

print("[OK] session tests passed\n")
