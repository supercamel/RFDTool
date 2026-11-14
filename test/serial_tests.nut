local GLib = import("GLib")
local DevicesMod = import("../src/serial/devices.nut")
local SerialMod = import("../src/serial/port.nut")
local SessionMod = import("../src/rfd/session.nut")

function check(name, condition) {
    if (!condition) throw "[FAIL] " + name
    print("[PASS] " + name + "\n")
}

class FakeDevice {
    path = "usb://temporary"
    permission = false
    function get_path() { return path }
    function get_name() { return "Test adapter" }
    function get_has_permission() { return permission }
}

class FakeManager {
    device = null
    callback = null
    requests = 0
    lookups = 0
    available = true
    mode = "grant"
    token = 0
    constructor() { device = FakeDevice() }
    function connect(signal, cb) { callback = cb; return 1 }
    function list_devices() { return available ? [device] : [] }
    function lookup(path) {
        lookups++
        if (!available || (path != "usb://temporary" && path != device.path)) throw "Device detached"
        return device
    }
    function cancel_permission() { token++ }
    function request_permission(path) {
        requests++
        if (mode == "error") throw "Permission request failed"
        if (mode == "wait") return true
        local self = this, generation = token
        sqgi.timeout_add(5, function() {
            if (generation != self.token) return false
            if (self.mode == "detach") self.available = false
            if (self.mode != "deny") {
                self.device.permission = true
                self.device.path = "usb://stable-serial/0"
            }
            self.callback(path, self.mode != "deny", "USB permission denied")
            return false
        })
        return true
    }
}

class FakePort {
    opened = false
    written = ""
    chunk = 2
    fail = false
    function set_baud(value) {}
    function set_timeout(value) {}
    function open_full(path) { if (fail) throw "Access denied"; opened = true; return true }
    function close() { opened = false }
    function is_open() { return opened }
    function bytes_available() { return 0 }
    function write_string(text) {
        local size = text.len() < chunk ? text.len() : chunk
        written += text.slice(0, size)
        return size
    }
}

local loop = GLib.MainLoop.new(null, false), failure = null
async function run() {
    local manager = FakeManager(), devices = DevicesMod.Devices(manager)
    check("enumeration does not request permission", devices.list().len() == 1 && manager.requests == 0)
    check("custom desktop path is preserved", (await devices.resolve("/dev/pts/9", false)) == "/dev/pts/9" && manager.lookups == 0)
    check("custom Windows COM path is preserved", (await devices.resolve("COM12", false)) == "COM12")
    check("USB permission refreshes device identity", (await devices.resolve("usb://temporary")) == "usb://stable-serial/0")
    check("permission request completes", manager.requests == 1 && !devices.waiting())
    await devices.resolve("usb://stable-serial/0")
    check("granted devices do not prompt again", manager.requests == 1)

    foreach (mode in ["deny", "detach", "error"]) {
        local m = FakeManager(), failed = false
        m.mode = mode
        local access = DevicesMod.Devices(m)
        try { await access.resolve("usb://temporary") } catch (e) { failed = true }
        check("permission " + mode + " cannot open a device", failed && !access.waiting())
    }
    manager = FakeManager(); manager.mode = "wait"
    devices = DevicesMod.Devices(manager)
    local access = devices
    sqgi.timeout_add(10, function() { access.cancel(); return false })
    check("permission cancellation stops connection", (await devices.resolve("usb://temporary")) == null)
    manager.callback("usb://temporary", true, "")
    check("late permission result is ignored", !devices.waiting())
    manager.mode = "grant"
    check("connection can retry after cancellation", (await devices.resolve("usb://temporary")) == "usb://stable-serial/0")
    manager.available = false
    check("removed devices disappear from enumeration", devices.list().len() == 0)
    local failed = false
    try { await devices.resolve("usb://stable-serial/0") } catch (e) { failed = true }
    check("missing selection never falls back to another port", failed)

    local native = FakePort(), states = []
    local serial = SerialMod.SerialPort(function() { return native })
    serial.set_state_callback(function(opened) { states.append(opened) })
    serial.open("test", 57600)
    check("partial writes preserve command bytes", serial.write("AT&W\r\n") == 6 && native.written == "AT&W\r\n")
    native.chunk = 0; failed = false
    try { serial.write("AT\r\n") } catch (e) { failed = true }
    check("zero-progress writes fail", failed)
    local session = SessionMod.RfdSession(serial)
    sqgi.timeout_add(5, function() { native.opened = false; return false })
    local started = GLib.get_monotonic_time()
    failed = false
    try { await session.wait_for_terminal(5000) } catch (e) { failed = true }
    await sqgi.sleep(30)
    check("detach updates connection state", !serial.connected && states.top() == false)
    check("detach aborts pending command promptly", failed && GLib.get_monotonic_time() - started < 1000000)
    native.fail = true; failed = false
    try { serial.open("test", 57600) } catch (e) { failed = e.tostring().find("Access denied") != null }
    check("native open errors remain actionable", failed && !serial.is_open())
    await SerialMod.drain_retired_ports()
    loop.quit()
}
run().catch(function(e) { failure = e; loop.quit() })
loop.run()
if (failure != null) throw failure
print("[OK] serial discovery, permission, and I/O tests passed\n")
